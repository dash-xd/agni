#!/usr/bin/env bash
set -Eeuo pipefail
action=${1:?action} scope=${2:?scope} probe=${3:?probe}
[[ "$scope" =~ ^[a-z][a-z0-9-]{0,31}$ ]]
[[ "$probe" =~ ^/nix/store/[a-z0-9]{32}-[^/]+/bin/fatline-services-probe$ ]]
[[ $(id -u) -ne 0 ]]
base="$HOME/.local/state/nix-xd/fatline/$scope"
apps="$base/services"
runtime="$base/credentials/runtime"
units="$HOME/.config/containers/systemd"
[[ $(findmnt -rn -o FSTYPE --mountpoint /var/mnt/nixstore) == 9p ]]
[[ ",$(findmnt -rn -o OPTIONS --mountpoint /var/mnt/nixstore)," == *,ro,* ]]
revoke_file() {
  [[ -f "$runtime/users.acl" ]] || return 0
  local temporary
  temporary=$(mktemp "$runtime/.acl.XXXXXX")
  awk '$1 == "user" && $2 == "bootstrap" { print "user bootstrap reset off"; next } { print }' "$runtime/users.acl" > "$temporary"
  chmod 600 "$temporary"
  mv -f "$temporary" "$runtime/users.acl"
}
aux_podman() {
  env -u NOTIFY_SOCKET -u PODMAN_SYSTEMD_UNIT -u LISTEN_PID -u LISTEN_FDS -u LISTEN_FDNAMES podman "$@"
}
bootstrap_container() {
  aux_podman run --sdnotify=ignore --rm --pull=never --name "$scope-bootstrap" --network none \
    --userns keep-id:uid=1000,gid=1000 --user 1000:1000 \
    --read-only --read-only-tmpfs=false --security-opt label=disable \
    --cap-drop all --security-opt no-new-privileges \
    --mount type=bind,src=/var/mnt/nixstore,dst=/nix/store,ro \
    --mount "type=bind,src=$base/socket,dst=/run/redis,ro" \
    --mount "type=bind,src=$apps/credentials/bootstrap,dst=/run/credentials,ro" \
    --rootfs "$apps/rootfs" "$probe" "$1" "$scope"
}
case "$action" in
  prepare)
    umask 077
    install -d -m 700 "$runtime"
    [[ $(awk '$1 == "user" && $2 == "bootstrap" { n++ } END { print n+0 }' "$apps/bootstrap-template.acl") == 1 ]]
    cp "$apps/bootstrap-template.acl" "$runtime/.starting.acl"
    chmod 600 "$runtime/.starting.acl"
    mv -f "$runtime/.starting.acl" "$runtime/users.acl"
    rm -f "$runtime/ready"
    ;;
  start)
    trap revoke_file EXIT
    bootstrap_container bootstrap
    revoke_file
    printf '%s\n' "${INVOCATION_ID:?systemd invocation required}" > "$runtime/ready"
    chmod 600 "$runtime/ready"
    echo FATLINE_REDIS_STARTUP=passed bootstrap=revoked
    ;;
  stop)
    aux_podman rm -f --ignore "$scope-bootstrap" >/dev/null
    revoke_file
    rm -f "$runtime/ready"
    ;;
  *) exit 2 ;;
esac
