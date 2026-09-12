#!/usr/bin/env bash
set -euo pipefail

# Local disposable security-cell backend for Smoke qualification.
# Agni owns placement mechanics only; the caller supplies exact source trees,
# Prajapati policy/identity artifacts, and every lifecycle transition.

cell_id="${AGNI_CELL_ID:-security-cell}"
case "$cell_id" in
  ''|*[!A-Za-z0-9_.-]*) echo "invalid AGNI_CELL_ID" >&2; exit 2 ;;
esac

root="${AGNI_CELL_ROOT:?AGNI_CELL_ROOT is required}"
marai_container="agni-${cell_id}-marai"
prajapati_container="agni-${cell_id}-prajapati"
logma_redis_container="agni-${cell_id}-logma-redis"
marai_image="${MARAI_IMAGE:-agni-${cell_id}-marai:local}"
prajapati_image="${PRAJAPATI_IMAGE:-agni-${cell_id}-prajapati:local}"
prajapati_port="${PRAJAPATI_PORT:-18081}"
logma_redis_port="${LOGMA_REDIS_PORT:-16379}"

app_dir="$root/marai-app"
admin_dir="$root/marai-admin"
prajapati_dir="$root/prajapati"

container_exists() {
  docker inspect "$1" >/dev/null 2>&1
}

wait_socket() {
  local path="$1"
  for _ in $(seq 1 150); do
    [[ -S "$path" ]] && return 0
    if ! docker inspect -f '{{.State.Running}}' "$marai_container" 2>/dev/null | grep -q true; then
      docker logs "$marai_container" >&2 || true
      return 1
    fi
    sleep 0.1
  done
  return 1
}

prepare_runtime() {
  umask 077
  rm -rf "$root"
  install -d -m 0700 "$root" "$admin_dir" "$prajapati_dir"
  install -d -m 0770 "$app_dir"

  head -c 48 /dev/urandom | base64 -w0 > "$admin_dir/admin.password"
  head -c 48 /dev/urandom | base64 -w0 > "$app_dir/app.password"
  chmod 0400 "$admin_dir/admin.password"
  chmod 0400 "$app_dir/app.password"

  cp "${PRAJAPATI_TENANT_REGISTRY_FILE:?PRAJAPATI_TENANT_REGISTRY_FILE is required}" "$prajapati_dir/tenants.json"
  cp "${PRAJAPATI_ED25519_KEYS_FILE:?PRAJAPATI_ED25519_KEYS_FILE is required}" "$prajapati_dir/keys.json"
  chmod 0444 "$prajapati_dir/tenants.json" "$prajapati_dir/keys.json"

  grep -q '"user"[[:space:]]*:[[:space:]]*"marai-app"' "$prajapati_dir/tenants.json"
  grep -q '"password_file"[[:space:]]*:[[:space:]]*"/run/marai/app.password"' "$prajapati_dir/tenants.json"
  if grep -q 'marai-admin' "$prajapati_dir/tenants.json"; then
    echo "Prajapati registry references marai-admin" >&2
    exit 1
  fi
}

prepare_marai_mount_ownership() {
  local marai_uid marai_gid
  marai_uid="$(docker run --rm --user 0:0 --entrypoint sh "$marai_image" -ceu 'id -u redis')"
  marai_gid="$(docker run --rm --user 0:0 --entrypoint sh "$marai_image" -ceu 'id -g redis')"

  case "$marai_uid:$marai_gid" in
    *[!0-9:]*|:*|*:) echo "invalid Marai runtime uid/gid: $marai_uid:$marai_gid" >&2; exit 1 ;;
  esac

  # Bind mounts replace the image's pre-owned /run/marai directory. Prepare the
  # host-backed directories for the image's actual redis uid/gid before startup
  # so Marai can create users.acl + redis.sock without running privileged.
  docker run --rm \
    -v "$app_dir:/app" \
    -v "$admin_dir:/admin" \
    alpine:3.22 sh -ceu '
      uid="$1"
      gid="$2"
      chown "$uid:$gid" /app /app/app.password /admin /admin/admin.password
      chmod 0770 /app
      chmod 0400 /app/app.password
      chmod 0700 /admin
      chmod 0400 /admin/admin.password
    ' -- "$marai_uid" "$marai_gid"
}

start() {
  : "${MARAI_DIR:?MARAI_DIR is required}"
  : "${PRAJAPATI_DIR:?PRAJAPATI_DIR is required}"

  for name in "$marai_container" "$prajapati_container" "$logma_redis_container"; do
    if container_exists "$name"; then
      echo "refusing to reuse existing container $name" >&2
      exit 1
    fi
  done

  prepare_runtime

  docker build -t "$marai_image" "$MARAI_DIR"
  docker build -t "$prajapati_image" "$PRAJAPATI_DIR"
  prepare_marai_mount_ownership

  docker run -d --name "$marai_container" \
    --network none \
    -v "$app_dir:/run/marai" \
    -v "$admin_dir:/run/marai-admin:ro" \
    -e MARAI_ADMIN_PASSWORD_FILE=/run/marai-admin/admin.password \
    -e MARAI_APP_PASSWORD_FILE=/run/marai/app.password \
    -e MARAI_REDIS_PORT=0 \
    -e MARAI_REDIS_SOCKET=/run/marai/redis.sock \
    -e MARAI_REDIS_SOCKET_MODE=660 \
    "$marai_image" >/dev/null

  wait_socket "$app_dir/redis.sock"

  # Root in a short-lived helper changes only the exact shared socket/app files
  # so Prajapati's unprivileged uid can read/connect. Admin material stays private.
  docker run --rm -v "$app_dir:/work" alpine:3.22 sh -ceu '
    chgrp 65532 /work /work/app.password /work/redis.sock
    chmod 0770 /work
    chmod 0440 /work/app.password
    chmod 0660 /work/redis.sock
  '

  docker run -d --name "$logma_redis_container" \
    -p "127.0.0.1:${logma_redis_port}:6379" \
    redis:7.2.5-alpine \
    redis-server --save '' --appendonly no >/dev/null

  docker run -d --name "$prajapati_container" \
    --network host \
    --user 65532:65532 \
    -v "$app_dir:/run/marai:ro" \
    -v "$prajapati_dir:/run/prajapati:ro" \
    -e PRAJAPATI_ALLOW_INSECURE_HTTP=1 \
    -e PRAJAPATI_LISTEN="127.0.0.1:${prajapati_port}" \
    -e PRAJAPATI_IDENTITY_PROVIDERS=ed25519 \
    -e PRAJAPATI_ED25519_KEYS_FILE=/run/prajapati/keys.json \
    -e PRAJAPATI_TENANT_REGISTRY_FILE=/run/prajapati/tenants.json \
    "$prajapati_image" >/dev/null

  printf 'cell_root=%s\n' "$root"
  printf 'marai_container=%s\n' "$marai_container"
  printf 'prajapati_container=%s\n' "$prajapati_container"
  printf 'logma_redis_container=%s\n' "$logma_redis_container"
  printf 'prajapati_url=http://127.0.0.1:%s\n' "$prajapati_port"
  printf 'logma_redis_addr=127.0.0.1:%s\n' "$logma_redis_port"
}

redis_as() {
  local user="$1"
  local password_file="$2"
  shift 2
  local password
  password="$(cat "$password_file")"
  docker exec -e REDISCLI_AUTH="$password" "$marai_container" \
    redis-cli -s /run/marai/redis.sock --user "$user" "$@"
}

lifecycle() {
  [[ $# -gt 0 ]] || { echo "lifecycle command required" >&2; exit 2; }
  redis_as marai-admin "$admin_dir/admin.password" "$@"
}

app() {
  [[ $# -gt 0 ]] || { echo "app command required" >&2; exit 2; }
  redis_as marai-app "$app_dir/app.password" "$@"
}

status() {
  for name in "$marai_container" "$prajapati_container" "$logma_redis_container"; do
    docker inspect -f '{{.Name}} {{.State.Status}}' "$name"
  done
}

stop() {
  # Exact identity cleanup only. Never discover by image/name prefix.
  docker rm -f "$prajapati_container" "$logma_redis_container" "$marai_container" >/dev/null 2>&1 || true
}

case "${1:-}" in
  start) start ;;
  lifecycle) shift; lifecycle "$@" ;;
  app) shift; app "$@" ;;
  status) status ;;
  stop) stop ;;
  *) echo "usage: $0 {start|lifecycle <redis command...>|app <redis command...>|status|stop}" >&2; exit 2 ;;
esac
