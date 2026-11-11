#!/usr/bin/env bash
set -Eeuo pipefail
action=${1:?action} scope=${2:?scope}
[[ "$scope" =~ ^[a-z][a-z0-9-]{0,31}$ ]]
[[ $(id -u) -ne 0 ]]
base="$HOME/.local/state/nix-xd/fatline/$scope"
apps="$base/services"
profile="$apps/profile"
units="$HOME/.config/containers/systemd"
if [[ "$action" == install ]]; then
  incoming=${3:?incoming}
  [[ "$incoming" == "$HOME/.local/state/nix-xd/"* && "$incoming" != *..* ]]
  source "$incoming/profile.env"
else
  source "$profile/profile.env"
fi
[[ "$profile_scope" == "$scope" ]]
[[ $(podman info --format '{{.Host.Security.Rootless}}') == true ]]
[[ $(findmnt -rn -o FSTYPE --mountpoint /var/mnt/nixstore) == 9p ]]
[[ ",$(findmnt -rn -o OPTIONS --mountpoint /var/mnt/nixstore)," == *,ro,* ]]
failed() {
  code=$?
  echo "FATLINE_STARTUP_PROFILE=failed action=$action status=$code" >&2
  journalctl --user --no-pager -n 40 -u "$scope-redis.service" -u "$scope-nginx.service" -u "$scope-logma.service" -u "$scope-skymill.service" || true
  exit "$code"
}
trap failed ERR
status() {
  for role in redis nginx logma skymill; do
    systemctl --user is-active --quiet "$scope-$role.service"
    [[ $(podman inspect "$scope-$role" --format '{{.State.Running}}') == true ]]
    [[ $(podman inspect "$scope-$role" --format '{{range .Mounts}}{{if eq .Destination "/nix/store"}}{{.RW}}{{end}}{{end}}') == false ]]
    if [[ "$role" == logma || "$role" == skymill ]]; then
      [[ -z $(podman port "$scope-$role") ]]
      [[ $(podman inspect "$scope-$role" --format '{{range .Mounts}}{{if eq .Destination "/run/credentials"}}{{.RW}}{{end}}{{end}}') == false ]]
    fi
  done
  invocation=$(systemctl --user show "$scope-redis.service" -p InvocationID --value)
  [[ -n "$invocation" && $(cat "$base/credentials/runtime/ready") == "$invocation" ]]
  grep -Fxq 'user bootstrap reset off' "$base/credentials/runtime/users.acl"
  [[ $(sha256sum "$base/credentials/users.acl" | cut -d ' ' -f 1) == "$profile_acl_digest" ]]
}
wait_ready() {
  deadline=$((SECONDS+180))
  while (( SECONDS<deadline )); do
    ready=1
    for role in redis nginx logma skymill; do
      state=$(systemctl --user show "$scope-$role.service" -p ActiveState --value)
      case "$state" in active) ;; activating|deactivating|reloading) ready=0 ;; *) echo "Startup failed: $scope-$role.service state=$state" >&2;return 1 ;; esac
    done
    (( ready==0 )) || return 0
    sleep 2
  done
  echo 'Startup readiness timed out' >&2;return 1
}
case "$action" in
  install)
    exec 9>"$base/lifecycle.lock";flock -x 9
    [[ $(sha256sum "$incoming/users.acl" | cut -d ' ' -f 1) == "$profile_acl_digest" ]]
    # Refuse an undeclared overlay instead of silently mixing startup profiles.
    shopt -s nullglob
    for role in redis nginx logma skymill; do
      for file in "$units/$scope-$role.container.d/"*; do
        case "${file##*/}" in 10-store-ready.conf|30-bootstrap.conf) ;; *) echo "Undeclared Quadlet drop-in: $file" >&2;exit 1 ;; esac
      done
    done
    for role in logma skymill nginx redis; do
      if [[ $(systemctl --user show "$scope-$role.service" -p LoadState --value) != not-found ]]; then
        systemctl --user stop "$scope-$role.service"
      fi
    done
    install -d -m 700 "$profile" "$base/socket" "$base/config" "$base/credentials/runtime" "$apps/state/logma" "$apps/credentials"
    for rootfs in "$base/rootfs" "$apps/rootfs"; do
      mkdir -p "$rootfs"
      if [[ ! -x "$rootfs/bin/busybox" ]]; then tar --no-same-owner -xpf "/var/mnt/nixstore/${profile_archive#/nix/store/}" -C "$rootfs";fi
      mkdir -p "$rootfs/run/redis" "$rootfs/run/credentials" "$rootfs/run/bootstrap-acl" "$rootfs/var/lib/logma/lifecycle"
      touch "$rootfs/etc/redis.conf" "$rootfs/etc/nginx.conf"
    done
    for role in logma skymill bootstrap; do
      install -d -m 700 "$apps/credentials/$role"
      for file in "$incoming/$role/"*; do install -m 600 "$file" "$apps/credentials/$role/${file##*/}";done
    done
    install -m 600 "$incoming/users.acl" "$base/credentials/users.acl"
    install -m 600 "$incoming/users.acl" "$apps/bootstrap-template.acl"
    install -m 700 "$profile_bundle/boot-wait.sh" "$apps/boot-wait.sh"
    install -m 600 "$incoming/profile.env" "$profile/profile.env"
    install -m 600 "$incoming/manifest.json" "$profile/manifest.json"
    install -m 600 "$incoming/redis.conf" "$base/config/redis.conf"
    install -m 600 "$incoming/nginx.conf" "$base/config/nginx.conf"
    install -m 600 "$incoming/$scope.network" "$units/$scope.network"
    for role in redis nginx logma skymill; do
      rm -f "$units/$scope-$role.container.d/10-store-ready.conf" "$units/$scope-$role.container.d/30-bootstrap.conf"
      install -m 600 "$incoming/$scope-$role.container" "$units/$scope-$role.container"
    done
    systemctl --user daemon-reload
    for role in redis nginx logma skymill; do [[ $(systemctl --user show "$scope-$role.service" -p LoadState --value) == loaded ]];done
    systemctl --user reset-failed "$scope-redis.service" "$scope-nginx.service" "$scope-logma.service" "$scope-skymill.service"
    systemctl --user start "$scope-logma.service" "$scope-skymill.service" "$scope-nginx.service"
    wait_ready
    status
    touch "$apps/active"
    echo FATLINE_STARTUP_PROFILE=passed
    ;;
  status) status;echo FATLINE_STARTUP_PROFILE_STATUS=passed ;;
  boot-prepare) status;echo FATLINE_REBOOT_PREPARED=passed ;;
  boot-check)
    wait_ready;status
    mount_time=$(systemctl show var-mnt-nixstore.mount -p ActiveEnterTimestampMonotonic --value)
    [[ "$mount_time" =~ ^[1-9][0-9]*$ ]]
    for role in redis nginx logma skymill; do
      start_time=$(systemctl --user show "$scope-$role.service" -p ExecMainStartTimestampMonotonic --value)
      [[ "$start_time" =~ ^[1-9][0-9]*$ && "$start_time" -ge "$mount_time" ]]
    done
    echo FATLINE_REBOOT_BOOTSTRAP=passed store_before_services=true bootstrap=revoked
    ;;
  *) echo 'Unsupported startup action' >&2;exit 2 ;;
esac
