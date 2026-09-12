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
marai_image="${MARAI_IMAGE:-agni-${cell_id}-marai:local}"
prajapati_image="${PRAJAPATI_IMAGE:-agni-${cell_id}-prajapati:local}"
prajapati_port="${PRAJAPATI_PORT:-18081}"

app_dir="$root/marai-app"
admin_dir="$root/marai-admin"
prajapati_dir="$root/prajapati"

container_exists() {
  docker inspect "$1" >/dev/null 2>&1
}

marai_diagnostics() {
  docker inspect -f 'marai state={{.State.Status}} running={{.State.Running}} exit={{.State.ExitCode}}' "$marai_container" >&2 || true
  docker exec "$marai_container" sh -ceu '
    id
    stat -c "%A %u:%g %n" /run/marai /run/marai-admin /run/marai/app.password /run/marai-admin/admin.password 2>/dev/null || true
    stat -c "%A %u:%g %n" /run/marai/redis.sock /run/marai/users.acl 2>/dev/null || true
  ' >&2 2>/dev/null || true
  docker logs "$marai_container" >&2 || true
}

prajapati_diagnostics() {
  docker inspect -f 'prajapati state={{.State.Status}} running={{.State.Running}} exit={{.State.ExitCode}} user={{.Config.User}}' "$prajapati_container" >&2 || true
  docker logs "$prajapati_container" >&2 || true
}

wait_socket() {
  for _ in $(seq 1 150); do
    # The host-backed app directory is intentionally owned by Marai's runtime
    # uid/gid and is not traversable by the unprivileged runner. Observe the
    # socket from inside the cell instead of weakening host filesystem modes.
    if docker exec "$marai_container" test -S /run/marai/redis.sock 2>/dev/null; then
      return 0
    fi
    if ! docker inspect -f '{{.State.Running}}' "$marai_container" 2>/dev/null | grep -q true; then
      marai_diagnostics
      return 1
    fi
    sleep 0.1
  done
  echo "Marai socket did not become ready" >&2
  marai_diagnostics
  return 1
}

wait_prajapati() {
  local status
  for _ in $(seq 1 100); do
    status="$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:${prajapati_port}/healthz" 2>/dev/null || true)"
    case "$status" in
      200|503) return 0 ;;
    esac
    if ! docker inspect -f '{{.State.Running}}' "$prajapati_container" 2>/dev/null | grep -q true; then
      prajapati_diagnostics
      return 1
    fi
    sleep 0.1
  done
  echo "Prajapati did not become reachable" >&2
  prajapati_diagnostics
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

prepare_prajapati_mount_access() {
  local runtime_user runtime_uid runtime_gid
  runtime_user="$(docker inspect -f '{{.Config.User}}' "$prajapati_image")"
  case "$runtime_user" in
    *:*)
      runtime_uid="${runtime_user%%:*}"
      runtime_gid="${runtime_user#*:}"
      ;;
    *)
      echo "Prajapati image must declare a numeric uid:gid USER; got: $runtime_user" >&2
      exit 1
      ;;
  esac
  case "$runtime_uid:$runtime_gid" in
    *[!0-9:]*|:*|*:) echo "invalid Prajapati runtime uid/gid: $runtime_uid:$runtime_gid" >&2; exit 1 ;;
  esac

  # Registry and verifier material is read-only policy input. Grant only the
  # image-declared runtime group traversal/read access; do not expose lifecycle
  # material and do not duplicate the image USER in docker run.
  docker run --rm -v "$prajapati_dir:/work" alpine:3.22 sh -ceu '
    gid="$1"
    chgrp "$gid" /work /work/tenants.json /work/keys.json
    chmod 0750 /work
    chmod 0440 /work/tenants.json /work/keys.json
  ' -- "$runtime_gid"
}

start() {
  : "${MARAI_DIR:?MARAI_DIR is required}"
  : "${PRAJAPATI_DIR:?PRAJAPATI_DIR is required}"

  for name in "$marai_container" "$prajapati_container"; do
    if container_exists "$name"; then
      echo "refusing to reuse existing container $name" >&2
      exit 1
    fi
  done

  prepare_runtime

  docker build -t "$marai_image" "$MARAI_DIR"
  docker build -t "$prajapati_image" "$PRAJAPATI_DIR"
  prepare_marai_mount_ownership
  prepare_prajapati_mount_access

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

  wait_socket

  # Root in a short-lived helper changes only the exact shared socket/app files
  # so Prajapati's unprivileged runtime group can read/connect. Admin material
  # stays private.
  prajapati_runtime_group="$(docker inspect -f '{{.Config.User}}' "$prajapati_image")"
  prajapati_runtime_group="${prajapati_runtime_group#*:}"
  docker run --rm -v "$app_dir:/work" alpine:3.22 sh -ceu '
    gid="$1"
    chgrp "$gid" /work /work/app.password /work/redis.sock
    chmod 0770 /work
    chmod 0440 /work/app.password
    chmod 0660 /work/redis.sock
  ' -- "$prajapati_runtime_group"

  docker run -d --name "$prajapati_container" \
    --network host \
    -v "$app_dir:/run/marai:ro" \
    -v "$prajapati_dir:/run/prajapati:ro" \
    -e PRAJAPATI_ALLOW_INSECURE_HTTP=1 \
    -e PRAJAPATI_LISTEN="127.0.0.1:${prajapati_port}" \
    -e PRAJAPATI_IDENTITY_PROVIDERS=ed25519 \
    -e PRAJAPATI_ED25519_KEYS_FILE=/run/prajapati/keys.json \
    -e PRAJAPATI_TENANT_REGISTRY_FILE=/run/prajapati/tenants.json \
    "$prajapati_image" >/dev/null

  # Placement is not complete until the process is reachable. A 503 is valid
  # here because Smoke has not yet activated Marai by creating its first key.
  wait_prajapati

  printf 'cell_root=%s\n' "$root"
  printf 'marai_container=%s\n' "$marai_container"
  printf 'prajapati_container=%s\n' "$prajapati_container"
  printf 'prajapati_url=http://127.0.0.1:%s\n' "$prajapati_port"
}

redis_as() {
  local user="$1"
  local password_file="$2"
  shift 2
  docker exec "$marai_container" sh -ceu '
    user="$1"
    password_file="$2"
    shift 2
    password="$(cat "$password_file")"
    REDISCLI_AUTH="$password" redis-cli -s /run/marai/redis.sock --user "$user" "$@"
  ' -- "$user" "$password_file" "$@"
}

lifecycle() {
  [[ $# -gt 0 ]] || { echo "lifecycle command required" >&2; exit 2; }
  redis_as marai-admin /run/marai-admin/admin.password "$@"
}

app() {
  [[ $# -gt 0 ]] || { echo "app command required" >&2; exit 2; }
  redis_as marai-app /run/marai/app.password "$@"
}

status() {
  for name in "$marai_container" "$prajapati_container"; do
    docker inspect -f '{{.Name}} {{.State.Status}}' "$name"
  done
}

stop() {
  # Exact identity cleanup only. Never discover by image/name prefix.
  docker rm -f "$prajapati_container" "$marai_container" >/dev/null 2>&1 || true
}

case "${1:-}" in
  start) start ;;
  lifecycle) shift; lifecycle "$@" ;;
  app) shift; app "$@" ;;
  status) status ;;
  stop) stop ;;
  *) echo "usage: $0 {start|lifecycle <redis command...>|app <redis command...>|status|stop}" >&2; exit 2 ;;
esac
