#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$scope" =~ ^[a-z][a-z0-9-]{0,31}$ ]]
[[ "$(cat /proc/sys/kernel/random/boot_id)" == "$boot" ]]
[[ "$(id -u)" != 0 ]]
[[ "$(podman info --format '{{.Host.Security.Rootless}}')" == true ]]
[[ "$(findmnt -rn -o FSTYPE --mountpoint /var/mnt/nixstore)" == 9p ]]
[[ ",$(findmnt -rn -o OPTIONS --mountpoint /var/mnt/nixstore)," == *,ro,* ]]
base="$HOME/.local/state/nix-xd/fatline/$scope"
apps="$base/services"
units="$HOME/.config/containers/systemd"
mkdir -p "$apps"; chmod 700 "$apps"
exec 9>"$base/lifecycle.lock"; flock -x 9
probe() {
  podman run --rm --pull=never --network "nix-xd-$scope" \
    --userns keep-id:uid=1000,gid=1000 --user 1000:1000 \
    --read-only --read-only-tmpfs=false --security-opt label=disable \
    --cap-drop all --security-opt no-new-privileges \
    --mount type=bind,src=/var/mnt/nixstore,dst=/nix/store,ro \
    --rootfs "$apps/rootfs" "$probe" qualify "$scope"
}
status() {
  for role in logma skymill; do
    systemctl --user is-active --quiet "$scope-$role.service"
    [[ "$(podman inspect "$scope-$role" --format '{{.State.Running}}')" == true ]]
    [[ -z "$(podman port "$scope-$role")" ]]
    [[ "$(podman inspect "$scope-$role" --format '{{range .Mounts}}{{if eq .Destination "/nix/store"}}{{.RW}}{{end}}{{end}}')" == false ]]
    [[ "$(podman inspect "$scope-$role" --format '{{range .Mounts}}{{if eq .Destination "/run/credentials"}}{{.RW}}{{end}}{{end}}')" == false ]]
    mounts="$(podman inspect "$scope-$role" --format '{{range .Mounts}}{{println .Source .Destination}}{{end}}')"
    grep -Fq "$apps/credentials/$role /run/credentials" <<< "$mounts"
    ! grep -Fq "$apps/credentials/bootstrap" <<< "$mounts"
    [[ "$(stat -c %a "$apps/credentials/$role")" == 700 ]]
    [[ "$(stat -c %a "$apps/credentials/$role/redis")" == 600 ]]
    if [[ "$role" == skymill ]]; then ! grep -Fq '/var/lib/logma/lifecycle' <<< "$mounts"; fi
  done
  [[ "$(sha256sum "$base/credentials/users.acl" | awk '{print $1}')" == "$new_acl_digest" ]]
  echo 'FATLINE_SERVICES_STATUS=passed private_http=true'
}
case "$action" in
  activate)
    if [[ -f "$apps/active" ]]; then status; echo FATLINE_SERVICES_ACTIVATED=reused; exit 0; fi
    current="$(sha256sum "$base/credentials/users.acl" | awk '{print $1}')"
    [[ "$current" == "$old_acl_digest" || "$current" == "$new_acl_digest" ]]
    [[ "$(sha256sum "$incoming/users.acl" | awk '{print $1}')" == "$new_acl_digest" ]]
    mkdir -p "$apps/rootfs" "$apps/state/logma" "$apps/credentials"
    chmod 700 "$apps/state" "$apps/state/logma" "$apps/credentials"
    if [[ ! -x "$apps/rootfs/bin/busybox" ]]; then tar --no-same-owner -xpf "/var/mnt/nixstore/${archive#/nix/store/}" -C "$apps/rootfs"; fi
    mkdir -p "$apps/rootfs/run/credentials" "$apps/rootfs/var/lib/logma/lifecycle"
    cp -R "$incoming/logma" "$incoming/skymill" "$incoming/bootstrap" "$apps/credentials/"
    chmod 700 "$apps/credentials/"{logma,skymill,bootstrap}
    chmod 600 "$apps/credentials/"{logma,skymill,bootstrap}/*
    # Activation adds ACL identities; the existing ephemeral Redis must restart once.
    systemctl --user stop "$scope-nginx.service" "$scope-redis.service"
    cp "$incoming/users.acl" "$base/credentials/users.acl"
    chmod 600 "$base/credentials/users.acl"
    systemctl --user start "$scope-redis.service" "$scope-nginx.service"
    for ((i=0;i<60;i++)); do [[ -S "$base/socket/redis.sock" ]] && break; sleep 1; done
    podman run --rm --pull=never --network none \
      --userns keep-id:uid=1000,gid=1000 --user 1000:1000 \
      --read-only --read-only-tmpfs=false --security-opt label=disable --cap-drop all --security-opt no-new-privileges \
      --mount type=bind,src=/var/mnt/nixstore,dst=/nix/store,ro \
      --mount "type=bind,src=$base/socket,dst=/run/redis,ro" \
      --mount "type=bind,src=$apps/credentials/bootstrap,dst=/run/credentials,ro" \
      --rootfs "$apps/rootfs" "$probe" bootstrap "$scope"
    for role in logma skymill; do
      executable="$logma"; [[ "$role" != skymill ]] || executable="$skymill"
      cat > "$units/$scope-$role.container" <<UNIT
[Unit]
Description=Scoped Fatline $role
Requires=$scope-redis.service
After=$scope-redis.service
[Container]
Rootfs=$apps/rootfs
ContainerName=$scope-$role
Network=$scope.network
NetworkAlias=$role
UserNS=keep-id:uid=1000,gid=1000
User=1000:1000
ReadOnly=true
PodmanArgs=--read-only-tmpfs=false --security-opt label=disable
NoNewPrivileges=true
DropCapability=all
Volume=/var/mnt/nixstore:/nix/store:ro
Volume=$base/socket:/run/redis:ro
Volume=$apps/credentials/$role:/run/credentials:ro
Tmpfs=/tmp:rw,nosuid,nodev,size=4m
Environment=FATLINE_SCOPE=$scope
UNIT
      if [[ "$role" == logma ]]; then
        cat >> "$units/$scope-$role.container" <<UNIT
Volume=$apps/state/logma:/var/lib/logma/lifecycle:rw
Environment=REDIS_NETWORK=unix
Environment=REDIS_SOCKET=/run/redis/redis.sock
Environment=REDIS_URI=unix:///run/redis/redis.sock
Environment=REDIS_USERNAME=logma
Environment=LOGMA_RATELIMITER_BOOTSTRAP=external
Environment=LOGMA_LIFECYCLE_STATE_DIR=/var/lib/logma/lifecycle
Environment=LOGMA_BIND_ADDR=0.0.0.0
Exec=/bin/sh -ec 'export REDISCLI_AUTH="\$(/bin/busybox cat /run/credentials/redis)"; export API_KEY="\$(/bin/busybox cat /run/credentials/api-key)"; exec "$executable"'
UNIT
      else
        cat >> "$units/$scope-$role.container" <<UNIT
Environment=REDIS_URL=unix:///run/redis/redis.sock
Environment=REDIS_USERNAME=skymill
Environment=REDIS_PASSWORD_FILE=/run/credentials/redis
Environment=SKYMILL_LISTEN_ADDR=0.0.0.0:8081
Environment=SKYMILL_SCOPED_PROVIDER=true
Environment=SKYMILL_STREAM=$scope:skymill:stream:github.webhooks
Exec=$executable
UNIT
      fi
      cat >> "$units/$scope-$role.container" <<UNIT
[Service]
Restart=on-failure
TimeoutStartSec=180
[Install]
WantedBy=default.target
UNIT
    done
    systemctl --user daemon-reload
    systemctl --user start "$scope-logma.service" "$scope-skymill.service"
    status
    touch "$apps/active"
    echo FATLINE_SERVICES_ACTIVATED=passed
    ;;
  qualify)
    status
    probe
    for role in logma skymill; do
      podman run --rm --pull=never --network none \
        --userns keep-id:uid=1000,gid=1000 --user 1000:1000 \
        --read-only --read-only-tmpfs=false --security-opt label=disable --cap-drop all --security-opt no-new-privileges \
        --mount type=bind,src=/var/mnt/nixstore,dst=/nix/store,ro \
        --mount "type=bind,src=$base/socket,dst=/run/redis,ro" \
        --mount "type=bind,src=$apps/credentials/$role,dst=/run/credentials,ro" \
        --rootfs "$apps/rootfs" "$probe" "security-$role" "$scope"
    done
    echo FATLINE_SERVICES_QUALIFICATION=passed
    ;;
  status) status ;;
  stop)
    for role in skymill logma; do
      if [[ "$(systemctl --user show "$scope-$role.service" -p LoadState --value)" != not-found ]]; then systemctl --user stop "$scope-$role.service"; fi
      if podman container exists "$scope-$role"; then [[ "$(podman inspect "$scope-$role" --format '{{.State.Running}}')" == false ]]; fi
    done
    rm -f "$units/$scope-logma.container" "$units/$scope-skymill.container"
    systemctl --user daemon-reload
    rm -f "$apps/active"
    echo FATLINE_SERVICES_STOPPED=passed
    ;;
  *) exit 2 ;;
esac
