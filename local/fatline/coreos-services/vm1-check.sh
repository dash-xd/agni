#!/usr/bin/env bash
set -Eeuo pipefail

action="${1:?expected inventory or store-check}"
scope="${2:?scope}"
[[ "$scope" =~ ^[a-z][a-z0-9-]{0,31}$ ]]
[[ "$(id -u)" != 0 ]]
[[ "$(podman info --format '{{.Host.Security.Rootless}}')" == true ]]
[[ "$(findmnt -rn -o FSTYPE --mountpoint /var/mnt/nixstore)" == 9p ]]
[[ ",$(findmnt -rn -o OPTIONS --mountpoint /var/mnt/nixstore)," == *,ro,* ]]

base="$HOME/.local/state/nix-xd/fatline/$scope"
apps="$base/services"
case "$action" in
  inventory)
    [[ $# == 2 ]]
    [[ -f "$base/credentials/users.acl" && -f "$base/config/redis.conf" ]]
    [[ -d "$apps" ]]
    profile=absent
    if [[ -f "$apps/profile/profile.env" && -f "$apps/bootstrap-template.acl" ]]; then
      [[ -f "$base/credentials/runtime/users.acl" && -f "$apps/profile/manifest.json" ]]
      profile=installed
    fi
    redis=inactive
    if systemctl --user is-active --quiet "$scope-redis.service"; then redis=active; fi
    units=0
    for role in logma skymill probot; do
      [[ ! -e "$HOME/.config/containers/systemd/$scope-$role.container" ]] || units=$((units+1))
    done
    for user in default publisher subscriber; do
      awk -v user="$user" '$1=="user" && $2==user {found++} END {exit found!=1}' "$base/credentials/users.acl"
    done
    grep -Fxq 'user default off' "$base/credentials/users.acl"
    printf 'AGNI_VM1_RUNTIME_INVENTORY=passed profile=%s redis=%s application_units=%s\n' "$profile" "$redis" "$units"
    ;;
  store-check)
    [[ $# == 8 ]] || { echo 'Expected three store paths, three revisions and a Node executable' >&2; exit 2; }
    shift 2
    for role in skymill logma probot; do
      executable="$1"; revision="$2";shift 2
      [[ "$revision" =~ ^[0-9a-f]{40}$ ]]
      [[ "$executable" =~ ^/nix/store/[a-z0-9]{32}-[a-zA-Z0-9._+-]+$ ]]
      guest="/var/mnt/nixstore/${executable#/nix/store/}"
      if [[ "$role" == probot ]]; then
        [[ -f "$guest/router/serve.js" ]]
      else
        [[ -f "$guest" && -x "$guest" ]]
      fi
      printf 'AGNI_VM1_STORE_ARTIFACT=passed role=%s revision=%s\n' "$role" "$revision"
    done
    [[ "$1" =~ ^/nix/store/[a-z0-9]{32}-[a-zA-Z0-9._+-]+/bin/node$ ]]
    [[ -x "/var/mnt/nixstore/${1#/nix/store/}" ]]
    echo 'AGNI_VM1_STORE_CHECK=passed'
    ;;
  *) echo 'Unsupported Agni VM1 guest check' >&2;exit 2;;
esac
