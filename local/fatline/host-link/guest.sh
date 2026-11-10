#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$scope" =~ ^[a-z][a-z0-9-]{0,31}$ && "$port" =~ ^[0-9]+$ ]]
[[ "$(cat /proc/sys/kernel/random/boot_id)" == "$boot" ]]
[[ "$(id -u)" != 0 ]]
[[ "$(podman info --format '{{.Host.Security.Rootless}}')" == true ]]
[[ "$(findmnt -rn -o FSTYPE --mountpoint /var/mnt/nixstore)" == 9p ]]
options="$(findmnt -rn -o OPTIONS --mountpoint /var/mnt/nixstore)"
[[ ",$options," == *,ro,* ]]
base="$HOME/.local/state/nix-xd/fatline/$scope"
units="$HOME/.config/containers/systemd"
mkdir -p "$base" "$units"
chmod 700 "$base"
exec 9>"$base/lifecycle.lock"
flock -x 9
if [[ "$action" == start || "$action" == status || "$action" == check || "$action" == publish ]]; then
  [[ "$(sha256sum "$base/credentials/users.acl" | awk '{print $1}')" == "$acl_digest" ]]
fi
case "$action" in
  prepare)
    [[ ! -e "$base/prepared" ]] || { echo 'Existing scope; stop it before replacement' >&2; exit 1; }
    mkdir -m 700 "$base/rootfs" "$base/socket" "$base/credentials" "$base/config"
    tar --extract --gzip --file "/var/mnt/nixstore/${archive#/nix/store/}" --directory "$base/rootfs" --no-same-owner --no-same-permissions
    chmod 755 "$base/rootfs"
    mkdir -p "$base/rootfs/run/redis" "$base/rootfs/run/credentials"
    touch "$base/rootfs/etc/redis.conf" "$base/rootfs/etc/nginx.conf"
    # The sole writable socket directory belongs to the rootless mapped service UID.
    cp "$incoming/users.acl" "$base/credentials/users.acl"
    cp "$incoming/publisher" "$base/credentials/publisher"
    cp "$incoming/publisher.json" "$base/credentials/publisher.json"
    chmod 600 "$base/credentials/"*
    [[ "$(sha256sum "$base/credentials/users.acl" | awk '{print $1}')" == "$acl_digest" ]]
    cp "$incoming/redis.conf" "$incoming/nginx.conf" "$base/config/"
    network="$units/$scope.network"
    [[ ! -e "$network" ]] || { echo 'Refusing an existing network unit' >&2; exit 1; }
    cat > "$network" <<UNIT
[Network]
NetworkName=nix-xd-$scope
Internal=true
UNIT
    for role in redis nginx; do
      file="$units/$scope-$role.container"
      [[ ! -e "$file" ]] || { echo 'Refusing to overwrite an existing unit' >&2; exit 1; }
      cat > "$file" <<UNIT
[Unit]
Description=Fatline host-link $scope $role
[Container]
ContainerName=$scope-$role
Rootfs=$base/rootfs
User=1000:1000
UserNS=keep-id:uid=1000,gid=1000
PodmanArgs=--read-only-tmpfs=false
ReadOnly=true
NoNewPrivileges=true
DropCapability=all
SecurityLabelDisable=true
Tmpfs=/tmp:rw,nosuid,nodev,mode=1777
Volume=/var/mnt/nixstore:/nix/store:ro
UNIT
      if [[ "$role" == redis ]]; then
        cat >> "$file" <<UNIT
Network=none
Volume=$base/socket:/run/redis:rw
Volume=$base/credentials/users.acl:/run/credentials/users.acl:ro
Volume=$base/config/redis.conf:/etc/redis.conf:ro
Exec=$redis/bin/redis-server /etc/redis.conf
UNIT
      else
        cat >> "$file" <<UNIT
Network=$scope.network
NetworkAlias=redis-proxy
PublishPort=127.0.0.1:$port:6379
Volume=$base/socket:/run/redis:ro
Volume=$base/config/nginx.conf:/etc/nginx.conf:ro
Exec=$nginx/bin/nginx -g "daemon off;" -c /etc/nginx.conf
UNIT
      fi
      cat >> "$file" <<'UNIT'
[Service]
Restart=on-failure
TimeoutStartSec=120
TimeoutStopSec=30
UNIT
    done
    touch "$base/prepared"
    systemctl --user daemon-reload
    echo 'FATLINE_HOST_LINK_PREPARED=true'
    ;;
  start)
    test -f "$base/prepared"
    systemctl --user start "$scope-redis.service"
    systemctl --user start "$scope-nginx.service"
    ready=0
    for attempt in {1..60}; do
      if [[ -S "$base/socket/redis.sock" ]]; then ready=1; break; fi
      sleep 1
    done
    [[ "$ready" == 1 ]] || { journalctl --user --no-pager -u "$scope-redis.service" -n 30; exit 1; }
    echo 'FATLINE_HOST_LINK_STARTED=true'
    ;;
  status)
    for role in redis nginx; do
      systemctl --user is-active "$scope-$role.service"
      test "$(podman inspect "$scope-$role" --format '{{.State.Running}}')" = true
    done
    stat -c 'SOCKET_MODE=%a OWNER=%u GROUP=%g' "$base/socket/redis.sock"
    [[ "$(podman network inspect "nix-xd-$scope" --format '{{.Internal}}')" == true ]]
    [[ "$(podman port "$scope-nginx" 6379/tcp)" == "127.0.0.1:$port" ]]
    [[ "$(podman inspect "$scope-redis" --format '{{.HostConfig.NetworkMode}}')" == none ]]
    [[ "$(stat -c %u "$base/socket/redis.sock")" == "$(id -u)" ]]
    [[ "$(stat -c %a "$base/credentials/users.acl")" == 600 ]]
    test "$(stat -c %a "$base/socket")" = 700
    test "$(stat -c %a "$base/socket/redis.sock")" = 600
    echo 'FATLINE_HOST_LINK_STATUS=passed'
    ;;
  check|publish)
    # A short-lived approved Unix client receives only its own credential files.
    podman run --rm --pull=never --network none \
      --userns keep-id:uid=1000,gid=1000 --user 1000:1000 \
      --read-only --read-only-tmpfs=false --security-opt label=disable --cap-drop all --security-opt no-new-privileges \
      --mount type=bind,src=/var/mnt/nixstore,dst=/nix/store,ro \
      --mount "type=bind,src=$base/socket,dst=/run/redis,ro" \
      --mount "type=bind,src=$base/credentials/publisher,dst=/run/credentials/publisher,ro" \
      --mount "type=bind,src=$base/credentials/publisher.json,dst=/run/credentials/publisher.json,ro" \
      --rootfs "$base/rootfs" "$client" --mode "$action" --config /run/credentials/publisher.json
    if [[ "$action" == check ]]; then
      # This UID is mapped to a different subordinate host UID; credentials are not needed.
      podman run --rm --pull=never --network none \
        --userns keep-id:uid=1000,gid=1000 --user 1001:1001 \
        --read-only --read-only-tmpfs=false --security-opt label=disable --cap-drop all --security-opt no-new-privileges \
        --mount type=bind,src=/var/mnt/nixstore,dst=/nix/store,ro \
        --mount "type=bind,src=$base/socket,dst=/run/redis,ro" \
        --rootfs "$base/rootfs" "$client" --mode deny-socket --socket /run/redis/redis.sock
      # Client and proxy mounts must never contain the Redis ACL credential directory.
      mounts="$(podman inspect "$scope-nginx" --format '{{range .Mounts}}{{println .Destination}}{{end}}')"
      ! grep -Eq '^/run/credentials(/|$)' <<< "$mounts"
      printf 'ACL_DIGEST=%s\n' "$acl_digest"
      echo 'FATLINE_HOST_LINK_SECURITY=passed'
    fi
    ;;
  stop)
    for role in nginx redis; do
      systemctl --user stop "$scope-$role.service"
      if podman container exists "$scope-$role"; then
        test "$(podman inspect "$scope-$role" --format '{{.State.Running}}')" = false
      fi
    done
    echo 'FATLINE_HOST_LINK_STOPPED=true'
    ;;
  *) echo 'Unknown host-link operation' >&2; exit 2 ;;
esac
