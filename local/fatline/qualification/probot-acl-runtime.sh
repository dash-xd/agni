#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

: "${AGNI_PROBOT_REDIS_RENDERER:?Select pinned Agni Redis ACL renderer}"
: "${AGNI_PROBOT_REDIS_PLANNER:?Select pinned policy generator}"
: "${AGNI_PROBOT_REDIS_BASELINE:?Select pinned baseline policy}"
: "${AGNI_PROBOT_SOURCES:?Select pinned source selection}"

work="$(mktemp -d "${TMPDIR:-/tmp}/agni-probot-acl.XXXXXXXX")"
pid=
cleanup() {
  if [[ -n "$pid" ]]; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  fi
  rm -rf -- "$work"
}
trap cleanup EXIT
python3 "$AGNI_PROBOT_REDIS_PLANNER" \
  --baseline "$AGNI_PROBOT_REDIS_BASELINE" \
  --sources "$AGNI_PROBOT_SOURCES" \
  --scope fatline-arm-vm1 \
  --output "$work/redis-policy.json"

mkdir -m 700 "$work/credentials" "$work/socket"
python3 - "$work/credentials" <<'PY'
import pathlib,secrets,sys
base=pathlib.Path(sys.argv[1])
for name in ("logma","skymill","bootstrap","probot_state","lifecycle_publish","lifecycle_subscribe"):
    (base/name).write_text(secrets.token_hex(32)+"\n")
    (base/name).chmod(0o600)
PY
python3 "$AGNI_PROBOT_REDIS_RENDERER" "$work/redis-policy.json" "$work/credentials" "$work/users.acl" >/dev/null
chmod 600 "$work/users.acl"

cat > "$work/redis.conf" <<EOF
port 0
protected-mode yes
unixsocket $work/socket/redis.sock
unixsocketperm 700
save ""
appendonly no
maxmemory 40mb
maxmemory-policy noeviction
aclfile $work/users.acl
daemonize no
EOF
redis-server "$work/redis.conf" >"$work/redis.log" 2>&1 &
pid=$!
for attempt in {1..40}; do
  [[ -S "$work/socket/redis.sock" ]] && break
  kill -0 "$pid" 2>/dev/null || { cat "$work/redis.log" >&2; exit 1; }
  sleep .1
done
[[ -S "$work/socket/redis.sock" ]] || { cat "$work/redis.log" >&2; exit 1; }

redis_as() {
  local user=$1
  shift
  local password
  password="$(< "$work/credentials/$user")"
  REDISCLI_AUTH="$password" redis-cli --no-auth-warning --raw \
    -s "$work/socket/redis.sock" --user "$user" "$@"
}
allowed() {
  local actual
  actual="$(redis_as "$@")"
  [[ "$actual" != *NOPERM* && "$actual" != *WRONGPASS* && "$actual" != *NOAUTH* && "$actual" != *ERR* ]] || {
    printf 'Allowed command rejected for %s: %s\n' "$1" "$actual" >&2
    exit 1
  }
}
denied() {
  local output
  output="$(redis_as "$@")"
  [[ "$output" == *NOPERM* ]] || {
    printf 'Expected NOPERM for %s, got: %s\n' "$1" "$output" >&2
    exit 1
  }
}

for user in logma skymill bootstrap probot_state lifecycle_publish lifecycle_subscribe; do
  [[ "$(redis_as "$user" PING)" == PONG ]]
  denied "$user" CONFIG GET maxmemory
  denied "$user" ACL LIST
done

tag="$(python3 - "$work/redis-policy.json" <<'PY'
import json,re,sys
data=json.load(open(sys.argv[1]))
pattern=data["users"]["skymill"]["keys"][0]
match=re.fullmatch(r"skymill:\{([0-9a-f]{32})\}:\*",pattern)
if not match: raise SystemExit("Unexpected Skymill slot")
print(match.group(1))
PY
)"
key="skymill:{$tag}:idempotency:qualify"
allowed skymill SET "$key" test
[[ "$(redis_as skymill GET "$key")" == test ]]
denied skymill GET foreign:key
denied skymill PUBLISH foreign:channel denied

state_key="xd-dash:fatline:runtime:probot-runtime:probot-test:qualification"
allowed probot_state HSET "$state_key" probe passed
[[ "$(redis_as probot_state HGET "$state_key" probe)" == passed ]]
denied probot_state GET foreign:key
denied probot_state PUBLISH fatline-arm-vm1:logma:lifecycle:probot-runtime:ready no

channel="fatline-arm-vm1:logma:lifecycle:probot-runtime:ready"
allowed lifecycle_publish PUBLISH "$channel" ping
denied lifecycle_publish PUBLISH foreign:channel ping
denied lifecycle_publish GET "$state_key"
denied lifecycle_subscribe PUBLISH "$channel" ping
denied lifecycle_subscribe GET "$state_key"
denied logma GET "$state_key"

echo 'AGNI_PROBOT_REDIS_ACL_RENDER=passed principals=6 secret_material=ephemeral'
echo 'AGNI_PROBOT_REDIS_ACL_ENFORCEMENT=passed scope=fatline-arm-vm1 redis=disposable'
echo 'AGNI_PROBOT_REDIS_RUNTIME=blocked reason=coreos-activation-and-real-credential-binding'
