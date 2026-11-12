#!/usr/bin/env bash
set -Eeuo pipefail

[[ "$(id -u)" != 0 ]] || { echo 'AGNI_PROBOT_GUEST_STORE=blocked reason=root-user' >&2; exit 1; }
[[ "$(podman info --format '{{.Host.Security.Rootless}}')" == true ]] || exit 1
[[ "$(findmnt -rn -o FSTYPE --mountpoint /var/mnt/nixstore)" == 9p ]] || exit 1
[[ ",$(findmnt -rn -o OPTIONS --mountpoint /var/mnt/nixstore)," == *,ro,* ]] || exit 1

: "${AGNI_PROBOT_GUEST_EXPECTED_BOOT:?Expected VM1 boot ID is required}"
[[ "$(< /proc/sys/kernel/random/boot_id)" == "$AGNI_PROBOT_GUEST_EXPECTED_BOOT" ]] || exit 1

check_binary() {
  local name="$1" expected_basename="$2" path="$3" sha="$4" guest
  [[ "$sha" =~ ^[a-f0-9]{40}$ ]] || exit 2
  [[ "$path" =~ ^/nix/store/[a-z0-9]{32}-[A-Za-z0-9._+-]+$ ]] || exit 2
  [[ "$path" == *-"$expected_basename" ]] || exit 2
  guest="/var/mnt/nixstore/${path#/nix/store/}"
  if [[ "$name" == probot-runtime ]]; then
    [[ -f "$guest/router/serve.js" ]] || exit 1
  else
    [[ -f "$guest" && -x "$guest" ]] || exit 1
  fi
  printf 'AGNI_PROBOT_GUEST_ARTIFACT=passed component=%s sha=%s\n' "$name" "$sha"
}

check_binary skymill skymill-http "${AGNI_PROBOT_GUEST_SKYMILL:?}" "${AGNI_PROBOT_GUEST_SKYMILL_SHA:?}"
check_binary logma logma-lifecycle "${AGNI_PROBOT_GUEST_LOGMA:?}" "${AGNI_PROBOT_GUEST_LOGMA_SHA:?}"
check_binary probot-runtime probot "${AGNI_PROBOT_GUEST_PROBOT:?}" "${AGNI_PROBOT_GUEST_PROBOT_SHA:?}"

node="${AGNI_PROBOT_GUEST_NODE:?Nix-store Node runtime required}"
[[ "$node" =~ ^/nix/store/[a-z0-9]{32}-[A-Za-z0-9._+-]+/bin/node$ ]] || exit 2
guest_node="/var/mnt/nixstore/${node#/nix/store/}"
[[ -f "$guest_node" && -x "$guest_node" ]] || exit 1
echo 'AGNI_PROBOT_GUEST_STORE=passed roles=3 node=visible mount=9p-ro'
