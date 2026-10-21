#!/usr/bin/env bash
set -euo pipefail

# Run from the flake directory, as mounted by Nix-Alpine.
# Keep mutable Git checkouts outside the immutable Nix store.
ROOT="${FATLINE_WORKSPACE:-$PWD/.fatline-workspace}"
SOURCES="$ROOT/sources"
LOCK="$ROOT/refs.lock"
mkdir -p "$ROOT"

# Branches are inputs for the initial bootstrap only. The resulting exact
# commit SHAs are saved in refs.lock and used for all subsequent commands.
names=(logma prajapati smoke)
repos=(xd-dash/logma xd-dash/prajapati xd-dash/smoke)
branches=(codex/group-strength-resources codex/fatline-authz-integration integration/smoke-reconcile-20261016)

bootstrap() {
  mkdir -p "$SOURCES"
  if [[ -e "$LOCK" ]]; then
    echo "Existing pin file: $LOCK" >&2
    echo "Remove it explicitly to rebootstrap different revisions." >&2
    exit 1
  fi
  local tmp
  tmp="$(mktemp "$ROOT/refs.lock.XXXXXX")"
  trap 'rm -f "$tmp"' RETURN
  for i in "${!names[@]}"; do
    local name="${names[$i]}" path="$SOURCES/${names[$i]}"
    if [[ ! -d "$path/.git" ]]; then
      git clone --branch "${branches[$i]}" --single-branch "https://github.com/${repos[$i]}.git" "$path"
    fi
    if [[ -n "$(git -C "$path" status --porcelain)" ]]; then
      echo "Dirty checkout: $path" >&2
      exit 1
    fi
    local sha
    sha="$(git -C "$path" rev-parse HEAD)"
    printf '%s %s\n' "$name" "$sha" >> "$tmp"
    echo "$name pinned at $sha"
  done
  mv "$tmp" "$LOCK"
  echo "Wrote $LOCK"
}

preflight() {
  [[ -f "$LOCK" ]] || { echo "Run bootstrap first" >&2; exit 1; }
  local name sha path current
  for name in "${names[@]}"; do
    sha="$(awk -v n="$name" '$1 == n {print $2}' "$LOCK")"
    [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo "Invalid/missing pin: $name" >&2; exit 1; }
    path="$SOURCES/$name"
    [[ -d "$path/.git" ]] || { echo "Missing checkout: $path" >&2; exit 1; }
    current="$(git -C "$path" rev-parse HEAD)"
    [[ "$current" == "$sha" ]] || { echo "Revision mismatch: $name" >&2; exit 1; }
    [[ -z "$(git -C "$path" status --porcelain)" ]] || { echo "Dirty checkout: $name" >&2; exit 1; }
    echo "$name $sha"
  done
}

advance_pin() {
  local name="${2:-}"
  local i path old new tmp
  for i in "${!names[@]}"; do
    [[ "${names[$i]}" == "$name" ]] && break
  done
  [[ "$i" =~ ^[0-9]+$ ]] && [[ "$i" -lt "${#names[@]}" ]] && [[ "${names[$i]}" == "$name" ]] || { echo "Usage: advance-pin {logma|prajapati|smoke}" >&2; return 2; }
  preflight
  path="$SOURCES/$name"
  old="$(git -C "$path" rev-parse HEAD)"
  git -C "$path" fetch origin "${branches[$i]}"
  new="$(git -C "$path" rev-parse FETCH_HEAD)"
  git -C "$path" merge-base --is-ancestor "$old" "$new" || { echo "Refusing non-fast-forward pin update" >&2; return 1; }
  git -C "$path" merge --ff-only "$new"
  tmp="$(mktemp "$ROOT/refs.lock.XXXXXX")"
  awk -v n="$name" -v sha="$new" '$1 == n {$2 = sha} {print $1, $2}' "$LOCK" > "$tmp"
  mv "$tmp" "$LOCK"
  echo "$name pin advanced: $old -> $new"
  preflight
}

build() {
  preflight
  for name in "${names[@]}"; do
    echo "Building $name"
    (cd "$SOURCES/$name" && GOWORK=off go build ./...)
  done
}

qualify() {
  preflight
  echo "Prajapati authorization package"
  (cd "$SOURCES/prajapati" && GOWORK=off go test ./authz)
  echo "Logma graph model"
  (cd "$SOURCES/logma" && GOWORK=off go test ./internal/pubsubmodel)
  echo "Smoke package compilation"
  (cd "$SOURCES/smoke" && GOWORK=off go build ./...)
  echo "Baseline complete. Cross-project HTTP enforcement is NOT tested yet."
}

qualify_integration() {
  preflight
  local tmp socket pid
  tmp="$(mktemp -d "${TMPDIR:-/tmp}/agni-fatline-redis.XXXXXXXX")"
  socket="$tmp/redis.sock"
  cleanup_redis() {
    if [[ -n "${pid:-}" ]]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
    rm -rf -- "$tmp"
  }
  trap cleanup_redis EXIT
  redis-server --port 0 --unixsocket "$socket" --save "" --appendonly no --maxmemory 40mb --maxmemory-policy noeviction --daemonize no --dir "$tmp" >"$tmp/redis.log" 2>&1 &
  pid=$!
  for _ in {1..100}; do
    if redis-cli -s "$socket" ping >/dev/null 2>&1; then break; fi
    if ! kill -0 "$pid" 2>/dev/null; then cat "$tmp/redis.log" >&2; return 1; fi
    sleep 0.05
  done
  redis-cli -s "$socket" ping >/dev/null
  echo "Isolated 40 MiB noeviction Redis ready: $socket"
  echo "Running Logma Redis reconnect and graph tests"
  (cd "$SOURCES/logma" && LOGMA_PUBSUBMODEL_REDIS_ADDR="$socket" GOWORK=off go test -count=1 ./internal/pubsubmodel -run 'TestRedisStoreReconnectPersistence|TestRedisStoreGraphRoundTrip')
  echo "Running Logma HTTP authorization boundary tests"
  (cd "$SOURCES/logma" && GOWORK=off go test -count=1 ./internal/routes -run '^TestPubSubVerifiedProjectBoundary$')
  echo "Fixture tests finished; real Prajapati binding and project-scoped Redis store remain unqualified." >&2
  return 1
}

case "${1:-}" in
  bootstrap|preflight|build|qualify) "$1" ;;
  qualify-integration) qualify_integration ;;
  advance-pin) advance_pin "$@" ;;
  *) echo "Usage: fatline.sh {bootstrap|preflight|build|qualify|qualify-integration|advance-pin}" >&2; exit 2 ;;
esac
