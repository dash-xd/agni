#!/usr/bin/env bash
set -Eeuo pipefail
action=${1:?action} scope=${2:?scope}
[[ "$scope" =~ ^[a-z][a-z0-9-]{0,31}$ ]]
[[ $(id -u) -ne 0 ]]
base="$HOME/.local/state/nix-xd/fatline/$scope"
apps="$base/services"
profile="$apps/profile"
units="$HOME/.config/containers/systemd"
if [[ "$action" == install || "$action" == install-probot ]]; then
  incoming=${3:?incoming}
  [[ "$incoming" == "$HOME/.local/state/nix-xd/"* && "$incoming" != *..* ]]
  source "$incoming/profile.env"
else
  source "$profile/profile.env"
fi
[[ "$profile_scope" == "$scope" ]]
profile_roles=${profile_roles:-redis nginx logma skymill}
case "$profile_roles" in
  "redis nginx logma skymill") [[ "$action" != install-probot ]] || { echo 'Five-role profile required' >&2; exit 2; };;
  "redis nginx logma skymill probot") [[ "$action" != install ]] || { echo 'Explicit install-probot action required' >&2; exit 2; };;
  *) echo 'Unexpected startup role graph' >&2; exit 2;;
esac
read -r -a roles <<< "$profile_roles"
app_roles=(nginx logma skymill)
if [[ "$profile_roles" == *" probot" ]]; then app_roles+=(probot); fi
all_units=()
app_units=()
for role in "${roles[@]}"; do all_units+=("$scope-$role.service"); done
for role in "${app_roles[@]}"; do app_units+=("$scope-$role.service"); done
[[ $(podman info --format '{{.Host.Security.Rootless}}') == true ]]
[[ $(findmnt -rn -o FSTYPE --mountpoint /var/mnt/nixstore) == 9p ]]
[[ ",$(findmnt -rn -o OPTIONS --mountpoint /var/mnt/nixstore)," == *,ro,* ]]
fault_dir="${XDG_RUNTIME_DIR:?user runtime directory required}/systemd/user/$scope-redis.service.d"
fault_file="$fault_dir/90-fatline-qualification.conf"
clear_fault() {
  if [[ -f "$fault_file" ]]; then
    rm -f "$fault_file"
    systemctl --user daemon-reload
  fi
}
failed() {
  code=$?
  trap - ERR
  if [[ "$action" == qualify-reliability ]]; then clear_fault || true;fi
  echo "FATLINE_STARTUP_PROFILE=failed action=$action status=$code" >&2
  journalctl --user --no-pager -n 40 "${all_units[@]/#/-u }" || true
  exit "$code"
}
trap failed ERR
trap 'if [[ "$action" == qualify-reliability ]]; then clear_fault;fi' EXIT
status() {
  for role in "${roles[@]}"; do
    systemctl --user is-active --quiet "$scope-$role.service"
    [[ $(podman inspect "$scope-$role" --format '{{.State.Running}}') == true ]]
    [[ $(podman inspect "$scope-$role" --format '{{range .Mounts}}{{if eq .Destination "/nix/store"}}{{.RW}}{{end}}{{end}}') == false ]]
    if [[ "$role" == logma || "$role" == skymill || "$role" == probot ]]; then
      [[ -z $(podman port "$scope-$role") ]]
      [[ $(podman inspect "$scope-$role" --format '{{range .Mounts}}{{if eq .Destination "/run/credentials"}}{{.RW}}{{end}}{{end}}') == false ]]
    fi
  done
  upheld=$(systemctl --user show "$scope-redis.service" -p Upholds --value)
  for role in "${app_roles[@]}"; do [[ " $upheld " == *" $scope-$role.service "* ]];done
  invocation=$(systemctl --user show "$scope-redis.service" -p InvocationID --value)
  [[ -n "$invocation" && $(cat "$base/credentials/runtime/ready") == "$invocation" ]]
  grep -Fxq 'user bootstrap reset off' "$base/credentials/runtime/users.acl"
  [[ $(sha256sum "$base/credentials/users.acl" | cut -d ' ' -f 1) == "$profile_acl_digest" ]]
}
wait_ready() {
  deadline=$((SECONDS+180))
  while (( SECONDS<deadline )); do
    ready=1
    for role in "${roles[@]}"; do
      state=$(systemctl --user show "$scope-$role.service" -p ActiveState --value)
      case "$state" in active) ;; activating|deactivating|reloading|inactive|failed) ready=0 ;; *) echo "Unexpected state: $scope-$role.service state=$state" >&2;return 1 ;; esac
    done
    (( ready==0 )) || return 0
    sleep 2
  done
  echo 'Startup readiness timed out' >&2;return 1
}
case "$action" in
  install|install-probot)
    exec 9>"$base/lifecycle.lock";flock -x 9
    [[ $(sha256sum "$incoming/users.acl" | cut -d ' ' -f 1) == "$profile_acl_digest" ]]
    for role in "${roles[@]}"; do
      [[ -s "$incoming/$scope-$role.container" ]] || { echo "Missing staged Quadlet: $role" >&2; exit 1; }
    done
    for role in logma skymill bootstrap; do
      [[ -d "$incoming/$role" && -s "$incoming/$role/redis" ]] || { echo "Missing staged credential: $role" >&2; exit 1; }
    done
    for principal in publisher subscriber; do
      existing=$(awk -v name="$principal" '$1=="user" && $2==name {print}' "$base/credentials/users.acl")
      candidate=$(awk -v name="$principal" '$1=="user" && $2==name {print}' "$incoming/users.acl")
      [[ -n "$existing" && "$existing" == "$candidate" ]] || { echo "Existing host-link identity changed: $principal" >&2; exit 1; }
    done
    if [[ "$action" == install-probot ]]; then
      [[ -s "$incoming/probot/state" && -s "$incoming/probot/publish" && -s "$incoming/probot/operator" &&
         -s "$incoming/probot/skymill-token" && -s "$incoming/skymill/http-token" ]] || {
        echo 'Incomplete five-role application credential staging' >&2; exit 1;
      }
      cmp -s "$incoming/probot/skymill-token" "$incoming/skymill/http-token" || {
        echo 'Skymill server/client HTTP authority mismatch' >&2; exit 1;
      }
    fi
    # Refuse an undeclared overlay instead of silently mixing startup profiles.
    shopt -s nullglob
    for role in "${roles[@]}"; do
      for file in "$units/$scope-$role.container.d/"*; do
        case "${file##*/}" in 10-store-ready.conf|30-bootstrap.conf) ;; *) echo "Undeclared Quadlet drop-in: $file" >&2;exit 1 ;; esac
      done
    done
    clear_fault
    stop_units=()
    for role in probot logma skymill nginx redis; do
      if [[ $(systemctl --user show "$scope-$role.service" -p LoadState --value) != not-found ]]; then
        stop_units+=("$scope-$role.service")
      fi
    done
    (( ${#stop_units[@]}==0 )) || systemctl --user stop "${stop_units[@]}"
    install -d -m 700 "$profile" "$base/socket" "$base/config" "$base/credentials/runtime" "$apps/state/logma" "$apps/credentials"
    for rootfs in "$base/rootfs" "$apps/rootfs"; do
      mkdir -p "$rootfs"
      if [[ ! -x "$rootfs/bin/busybox" ]]; then tar --no-same-owner -xpf "/var/mnt/nixstore/${profile_archive#/nix/store/}" -C "$rootfs";fi
      mkdir -p "$rootfs/run/redis" "$rootfs/run/credentials" "$rootfs/run/bootstrap-acl" "$rootfs/var/lib/logma/lifecycle"
      touch "$rootfs/etc/redis.conf" "$rootfs/etc/nginx.conf"
    done
    credential_roles=(logma skymill bootstrap)
    if [[ "$action" == install-probot ]]; then credential_roles+=(probot); fi
    for role in "${credential_roles[@]}"; do
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
    for role in "${roles[@]}"; do
      rm -f "$units/$scope-$role.container.d/10-store-ready.conf" "$units/$scope-$role.container.d/30-bootstrap.conf"
      install -m 600 "$incoming/$scope-$role.container" "$units/$scope-$role.container"
    done
    systemctl --user daemon-reload
    for role in "${roles[@]}"; do [[ $(systemctl --user show "$scope-$role.service" -p LoadState --value) == loaded ]];done
    reset_units=()
    start_units=()
    for role in "${roles[@]}"; do reset_units+=("$scope-$role.service"); done
    for role in "${app_roles[@]}"; do start_units+=("$scope-$role.service"); done
    systemctl --user reset-failed "${reset_units[@]}"
    systemctl --user start "${start_units[@]}"
    wait_ready
    status
    touch "$apps/active"
    if [[ "$action" == install-probot ]]; then
      echo FATLINE_PROBOT_PROFILE_ACTIVATION=passed roles=5 redis_restart=explicit
    fi
    echo FATLINE_STARTUP_PROFILE=passed
    ;;
  recover)
    exec 9>"$base/lifecycle.lock";flock -x 9
    clear_fault
    systemctl --user reset-failed "${all_units[@]}"
    systemctl --user start "$scope-redis.service"
    wait_ready;status
    bash "$profile_bundle/bootstrap.sh" verify "$scope" "$profile_probe"
    echo FATLINE_PROFILE_RECOVERY=passed
    ;;
  qualify-reliability)
    exec 9>"$base/lifecycle.lock";flock -x 9
    status
    [[ ! -e "$fault_file" ]]
    boot=$(cat /proc/sys/kernel/random/boot_id)
    acl_before=$(sha256sum "$apps/bootstrap-template.acl")
    # The runtime-only override fails the bootstrap hook without modifying credentials.
    systemctl --user stop "$scope-redis.service"
    install -d -m 700 "$fault_dir"
    printf '[Service]\nRestart=no\nExecStartPost=\nExecStartPost=/bin/false\n' > "$fault_file"
    systemctl --user daemon-reload
    systemctl --user reset-failed "${all_units[@]}"
    if systemctl --user start "${app_units[@]}"; then
      echo 'Bootstrap failure unexpectedly allowed startup' >&2;exit 1
    fi
    [[ $(systemctl --user show "$scope-redis.service" -p ActiveState --value) == failed ]]
    [[ ! -e "$base/credentials/runtime/ready" ]]
    grep -Fxq 'user bootstrap reset off' "$base/credentials/runtime/users.acl"
    for role in "${app_roles[@]}"; do
      if systemctl --user is-active --quiet "$scope-$role.service"; then
        echo "Bootstrap failure left $scope-$role.service active" >&2;exit 1
      fi
      if podman container exists "$scope-$role"; then
        [[ $(podman inspect "$scope-$role" --format '{{.State.Running}}') == false ]]
      fi
    done
    echo FATLINE_BOOTSTRAP_FAILURE=passed dependents=blocked
    clear_fault
    systemctl --user reset-failed "${all_units[@]}"
    systemctl --user start "$scope-redis.service"
    wait_ready;status
    bash "$profile_bundle/bootstrap.sh" verify "$scope" "$profile_probe"
    echo FATLINE_BOOTSTRAP_RECOVERY=passed bootstrap=revoked
    before=$(systemctl --user show "$scope-redis.service" -p InvocationID --value)
    for role in "${roles[@]}"; do podman inspect "$scope-$role" --format '{{.Id}}';done > "$apps/crash-before.ids"
    podman kill --signal KILL "$scope-redis" >/dev/null
    # Observe a new successful invocation, without controller start/recover calls.
    deadline=$((SECONDS+180))
    changed=false
    while (( SECONDS<deadline )); do
      after=$(systemctl --user show "$scope-redis.service" -p InvocationID --value)
      if [[ -n "$after" && "$after" != "$before" && -f "$base/credentials/runtime/ready" && $(cat "$base/credentials/runtime/ready") == "$after" ]]; then changed=true;break;fi
      sleep 2
    done
    [[ "$changed" == true ]]
    wait_ready;status
    bash "$profile_bundle/bootstrap.sh" verify "$scope" "$profile_probe"
    for role in "${roles[@]}"; do podman inspect "$scope-$role" --format '{{.Id}}';done > "$apps/crash-after.ids"
    [[ $(sort "$apps/crash-before.ids" "$apps/crash-after.ids" | uniq -d | wc -l) == 0 ]]
    [[ $(cat /proc/sys/kernel/random/boot_id) == "$boot" ]]
    [[ $(sha256sum "$apps/bootstrap-template.acl") == "$acl_before" ]]
    echo FATLINE_PROFILE_RELIABILITY=passed bootstrap_failure=blocked redis_crash=automatic boot=unchanged
    ;;
  status) status;echo FATLINE_STARTUP_PROFILE_STATUS=passed ;;
  boot-prepare) status;echo FATLINE_REBOOT_PREPARED=passed ;;
  boot-check)
    wait_ready;status
    mount_time=$(systemctl show var-mnt-nixstore.mount -p ActiveEnterTimestampMonotonic --value)
    [[ "$mount_time" =~ ^[1-9][0-9]*$ ]]
    for role in "${roles[@]}"; do
      start_time=$(systemctl --user show "$scope-$role.service" -p ExecMainStartTimestampMonotonic --value)
      [[ "$start_time" =~ ^[1-9][0-9]*$ && "$start_time" -ge "$mount_time" ]]
    done
    echo FATLINE_REBOOT_BOOTSTRAP=passed store_before_services=true bootstrap=revoked
    ;;
  *) echo 'Unsupported startup action' >&2;exit 2 ;;
esac
