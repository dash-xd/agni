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
check_graph() {
  local role property dependency
  for role in redis nginx logma skymill; do
    [[ $(systemctl --user show "$scope-$role.service" -p LoadState --value) == loaded ]]
    if [[ "$role" != redis ]]; then
      for property in Requires After PartOf BindsTo; do
        systemctl --user show "$scope-$role.service" -p "$property" --value |
          tr ' ' '\n' | grep -Fxq "$scope-redis.service"
      done
    fi
  done
  for property in Requires After; do
    systemctl --user show "$scope-logma.service" -p "$property" --value |
      tr ' ' '\n' | grep -Fxq "$scope-nginx.service"
  done
  systemctl --user show "$scope-redis.service" -p ExecStartPre --value | grep -Fq "service-prepare $scope $probe"
  systemctl --user show "$scope-redis.service" -p ExecStartPost --value | grep -Fq "service-bootstrap $scope $probe"
  systemctl --user show "$scope-redis.service" -p ExecStopPost --value | grep -Fq "service-stop $scope $probe"
}
wait_ready() {
  local role state job ready deadline=$((SECONDS + 180))
  while (( SECONDS < deadline )); do
    ready=1
    for role in redis nginx logma skymill; do
      state=$(systemctl --user show "$scope-$role.service" -p ActiveState --value)
      case "$state" in
        active) ;;
        activating|reloading|deactivating) ready=0 ;;
        inactive)
          job=$(systemctl --user show "$scope-$role.service" -p Job --value)
          [[ "$job" =~ ^[1-9][0-9]* ]] || { echo "Restart propagation missing: $scope-$role.service" >&2; return 1; }
          ready=0 ;;
        *) echo "Restart unit failed: $scope-$role.service state=$state" >&2; return 1 ;;
      esac
    done
    if (( ready == 1 )); then echo FATLINE_RESTART_CONSUMERS=ready; return 0; fi
    sleep 2
  done
  echo 'Restart readiness timed out after 180 seconds' >&2
  return 1
}
case "$action" in
  graph-check) check_graph ;;
  boot-prepare)
    exec 9>"$base/lifecycle.lock"; flock -x 9
    check_graph
    script=$(realpath "$0")
    install -m 700 "$(dirname "$script")/boot-wait.sh" "$apps/.boot-wait.sh.new"
    mv -f "$apps/.boot-wait.sh.new" "$apps/boot-wait.sh"
    for role in redis nginx logma skymill; do
      install -d -m 700 "$units/$scope-$role.container.d"
      cat > "$units/$scope-$role.container.d/10-store-ready.conf" <<UNIT
[Service]
ExecStartPre=/bin/bash $apps/boot-wait.sh $scope $probe
TimeoutStartSec=300
UNIT
    done
    systemctl --user daemon-reload
    check_graph
    for role in logma skymill; do
      systemctl --user list-dependencies --plain --no-pager default.target | grep -Fq "$scope-$role.service"
    done
    echo FATLINE_REBOOT_PREPARED=passed
    ;;
  boot-check)
    cmp -s "$(dirname "$(realpath "$0")")/boot-wait.sh" "$apps/boot-wait.sh"
    for role in redis nginx logma skymill; do
      systemctl --user show "$scope-$role.service" -p ExecStartPre --value | grep -Fq "$apps/boot-wait.sh $scope $probe"
    done
    check_graph
    wait_ready
    invocation=$(systemctl --user show "$scope-redis.service" -p InvocationID --value)
    [[ -n "$invocation" && $(cat "$runtime/ready") == "$invocation" ]]
    grep -Fxq 'user bootstrap reset off' "$runtime/users.acl"
    bootstrap_container bootstrap-denied
    mount_time=$(systemctl show var-mnt-nixstore.mount -p ActiveEnterTimestampMonotonic --value)
    [[ "$mount_time" =~ ^[1-9][0-9]*$ ]]
    for role in redis nginx logma skymill; do
      start_time=$(systemctl --user show "$scope-$role.service" -p ExecMainStartTimestampMonotonic --value)
      [[ "$start_time" =~ ^[1-9][0-9]*$ && "$start_time" -ge "$mount_time" ]]
    done
    echo FATLINE_REBOOT_BOOTSTRAP=passed store_before_services=true bootstrap=revoked
    ;;
  wait-ready) wait_ready ;;
  service-prepare)
    umask 077
    install -d -m 700 "$runtime"
    [[ $(awk '$1 == "user" && $2 == "bootstrap" { n++ } END { print n+0 }' "$apps/bootstrap-template.acl") == 1 ]]
    cp "$apps/bootstrap-template.acl" "$runtime/.starting.acl"
    chmod 600 "$runtime/.starting.acl"
    mv -f "$runtime/.starting.acl" "$runtime/users.acl"
    rm -f "$runtime/ready"
    ;;
  service-bootstrap)
    trap revoke_file EXIT
    bootstrap_container bootstrap
    revoke_file
    printf '%s\n' "${INVOCATION_ID:?systemd invocation required}" > "$runtime/ready"
    chmod 600 "$runtime/ready"
    echo FATLINE_REDIS_STARTUP=passed bootstrap=revoked
    ;;
  service-stop)
    aux_podman rm -f --ignore "$scope-bootstrap" >/dev/null
    revoke_file
    rm -f "$runtime/ready"
    ;;
  install)
    exec 9>"$base/lifecycle.lock"; flock -x 9
    test -f "$apps/active"
    [[ $(sha256sum "$base/credentials/users.acl" | awk '{print $1}') == "${4:?ACL digest}" ]]
    # Unit metadata and the template hold hashes; role passwords stay in private mounts.
    cp "$base/credentials/users.acl" "$apps/bootstrap-template.acl"
    chmod 600 "$apps/bootstrap-template.acl"
    script=$(realpath "$0")
    [[ "$script" == /var/mnt/nixstore/*/recovery.sh ]]
    install -d -m 700 "$runtime" "$units/$scope-redis.container.d"
    grep -Fxq 'aclfile /run/credentials/users.acl' "$base/config/redis.conf" ||
      grep -Fxq 'aclfile /run/bootstrap-acl/users.acl' "$base/config/redis.conf"
    sed -i 's|^aclfile /run/credentials/users.acl$|aclfile /run/bootstrap-acl/users.acl|' "$base/config/redis.conf"
    cat > "$units/$scope-redis.container.d/30-bootstrap.conf" <<UNIT
[Container]
Volume=$runtime:/run/bootstrap-acl:ro
[Service]
TimeoutStartSec=240
ExecStartPre=/bin/bash $script service-prepare $scope $probe
ExecStartPost=/bin/bash $script service-bootstrap $scope $probe
ExecStopPost=/bin/bash $script service-stop $scope $probe
UNIT
    for role in nginx logma skymill; do
      install -d -m 700 "$units/$scope-$role.container.d"
      cat > "$units/$scope-$role.container.d/30-bootstrap.conf" <<UNIT
[Unit]
Requires=$scope-redis.service
After=$scope-redis.service
PartOf=$scope-redis.service
BindsTo=$scope-redis.service
UNIT
      if [[ "$role" == logma ]]; then
        cat >> "$units/$scope-$role.container.d/30-bootstrap.conf" <<UNIT
Requires=$scope-nginx.service
After=$scope-nginx.service
UNIT
      fi
    done
    systemctl --user daemon-reload
    check_graph
    echo FATLINE_RESTART_GRAPH=installed runtime=unchanged
    ;;
  recover)
    exec 9>"$base/lifecycle.lock"; flock -x 9
    check_graph
    echo FATLINE_RESTART_RECOVERY=starting
    systemctl --user stop "$scope-logma.service" "$scope-skymill.service" "$scope-nginx.service"
    systemctl --user reset-failed "$scope-redis.service" "$scope-nginx.service" "$scope-logma.service" "$scope-skymill.service"
    systemctl --user start "$scope-redis.service" "$scope-nginx.service" "$scope-logma.service" "$scope-skymill.service"
    invocation=$(systemctl --user show "$scope-redis.service" -p InvocationID --value)
    [[ -n "$invocation" && $(cat "$runtime/ready") == "$invocation" ]]
    grep -Fxq 'user bootstrap reset off' "$runtime/users.acl"
    bootstrap_container bootstrap-denied
    for role in redis nginx logma skymill; do systemctl --user is-active --quiet "$scope-$role.service"; done
    echo FATLINE_RESTART_RECOVERED=passed
    ;;
  qualify)
    exec 9>"$base/lifecycle.lock"; flock -x 9
    boot=$(cat /proc/sys/kernel/random/boot_id)
    before=$(systemctl --user show "$scope-redis.service" -p InvocationID --value)
    for role in redis nginx logma skymill; do
      systemctl --user is-active --quiet "$scope-$role.service"
      podman inspect "$scope-$role" --format '{{.Id}}'
    done > "$apps/restart-before.ids"
    # Explicitly stop the dependency group before Redis: this also covers adoption
    # from an old active generation that predates the PartOf relationship.
    systemctl --user stop "$scope-logma.service" "$scope-skymill.service" "$scope-nginx.service"
    systemctl --user restart "$scope-redis.service"
    systemctl --user start "$scope-logma.service" "$scope-skymill.service" "$scope-nginx.service"
    after=$(systemctl --user show "$scope-redis.service" -p InvocationID --value)
    [[ -n "$after" && "$after" != "$before" && $(cat "$runtime/ready") == "$after" ]]
    [[ $(cat /proc/sys/kernel/random/boot_id) == "$boot" ]]
    grep -Fxq 'user bootstrap reset off' "$runtime/users.acl"
    [[ $(stat -c %a "$runtime/users.acl") == 600 ]]
    bootstrap_container bootstrap-denied
    for role in redis nginx logma skymill; do
      systemctl --user is-active --quiet "$scope-$role.service"
      podman inspect "$scope-$role" --format '{{.Id}}'
    done > "$apps/restart-after.ids"
    [[ $(sort "$apps/restart-before.ids" "$apps/restart-after.ids" | uniq -d | wc -l) == 0 ]]
    # A second restart exercises PartOf propagation with all consumers active.
    before=$after
    cp "$apps/restart-after.ids" "$apps/restart-before.ids"
    systemctl --user restart "$scope-redis.service"
    wait_ready
    after=$(systemctl --user show "$scope-redis.service" -p InvocationID --value)
    [[ -n "$after" && "$after" != "$before" && $(cat "$runtime/ready") == "$after" ]]
    [[ $(cat /proc/sys/kernel/random/boot_id) == "$boot" ]]
    bootstrap_container bootstrap-denied
    grep -Fxq 'user bootstrap reset off' "$runtime/users.acl"
    for role in redis nginx logma skymill; do
      systemctl --user is-active --quiet "$scope-$role.service"
      podman inspect "$scope-$role" --format '{{.Id}}'
    done > "$apps/restart-after.ids"
    [[ $(sort "$apps/restart-before.ids" "$apps/restart-after.ids" | uniq -d | wc -l) == 0 ]]
    echo FATLINE_REDIS_RESTART=passed bootstrap=revoked_on_disk_and_runtime boot=unchanged
    ;;
  *) exit 2 ;;
esac
