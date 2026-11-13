#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

action=${1:?Select verify, stage, status or activate}
scope=${2:?Select service scope}
bundle_store=${3:-}
[[ "$scope" == fatline-arm-vm1 ]] || exit 2
[[ "$(id -u)" != 0 ]]
[[ "$(podman info --format '{{.Host.Security.Rootless}}')" == true ]]
[[ "$(findmnt -rn -o FSTYPE --mountpoint /var/mnt/nixstore)" == 9p ]]
[[ ",$(findmnt -rn -o OPTIONS --mountpoint /var/mnt/nixstore)," == *,ro,* ]]
base="$HOME/.local/state/nix-xd/fatline/$scope"
apps="$base/services"
tool_store="@AGNI_PROBOT_GUEST_TOOL_STORE@"
tools="/var/mnt/nixstore/${tool_store#/nix/store/}"
[[ -s "$tools/probot-guest-stage.sh" && -s "$tools/probot-stage.py" ]] || {
  echo "AGNI_PROBOT_GUEST=blocked reason=guest-tools-not-visible" >&2; exit 1;
}

check_bundle() {
  [[ "$bundle_store" =~ ^/nix/store/[0-9a-z]{32}-candidate$ ]] || {
    echo "Expected a rooted immutable guest-bundle store path" >&2; exit 2;
  }
  candidate_store="/var/mnt/nixstore/${bundle_store#/nix/store/}"
  [[ -d "$candidate_store" && -s "$candidate_store/SHA256SUMS" ]] || {
    echo "AGNI_PROBOT_GUEST=blocked reason=store-bundle-unavailable" >&2; exit 1;
  }
  (cd "$candidate_store" && sha256sum --status -c SHA256SUMS)
  [[ -s "$candidate_store/artifacts.tsv" && -s "$candidate_store/guest-plan.json" ]]
  expected=0
  while IFS=$'\t' read -r role path revision; do
    [[ "$path" =~ ^/nix/store/[0-9a-z]{32}-[A-Za-z0-9._+-]+(/bin/node)?$ ]] || exit 2
    guest="/var/mnt/nixstore/${path#/nix/store/}"
    case "$role" in
      skymill|logma)
        [[ "$revision" =~ ^[0-9a-f]{40}$ && -f "$guest" && -x "$guest" ]]
        ;;
      probot-runtime)
        [[ "$revision" =~ ^[0-9a-f]{40}$ && -f "$guest/router/serve.js" ]]
        ;;
      node)
        [[ "$revision" == node && "$path" == */bin/node && -x "$guest" ]]
        ;;
      *) echo "Unexpected store component" >&2;exit 2 ;;
    esac
    expected=$((expected+1))
  done < "$candidate_store/artifacts.tsv"
  [[ "$expected" == 4 ]] || exit 1
  echo 'AGNI_PROBOT_GUEST_BUNDLE=passed roles=3 node=visible credentials=excluded'
}

case "$action" in
  verify)
    [[ $# == 3 ]]
    check_bundle
    echo 'AGNI_PROBOT_GUEST_VERIFY=passed activation=blocked'
    ;;
  stage)
    [[ $# == 3 ]]
    check_bundle
    [[ -s "$apps/profile/manifest.json" && -s "$apps/profile/profile.env" ]] || {
      echo 'AGNI_PROBOT_GUEST_STAGE=blocked reason=base-startup-profile-not-installed' >&2
      exit 1
    }
    [[ -d "$apps/credentials/logma" && -d "$apps/credentials/skymill" && -d "$apps/credentials/bootstrap" ]] || {
      echo 'AGNI_PROBOT_GUEST_STAGE=blocked reason=prior-service-credentials-missing' >&2
      exit 1
    }
    selected_spec="$(sha256sum "$apps/profile/manifest.json" | cut -d ' ' -f 1)"
    current_acl="$(sha256sum "$base/credentials/users.acl" | cut -d ' ' -f 1)"
    target="$apps/probot-candidates/${bundle_store##*/}-$selected_spec-$current_acl"
    if [[ -s "$target/rendered/profile.env" ]]; then
      echo "AGNI_PROBOT_GUEST_STAGE=reused candidate=$target activation=blocked"
      exit 0
    fi
    [[ ! -e "$target" ]] || {
      echo 'AGNI_PROBOT_GUEST_STAGE=blocked reason=incomplete-candidate-generation' >&2
      exit 1
    }
    mkdir -m 700 -p "$target/input"
    cp "$apps/profile/manifest.json" "$target/input/spec.json"
    cp "$candidate_store/artifacts.json" "$target/input/artifacts.json"
    cp "$candidate_store/sources.json" "$target/input/sources.json"
    cp "$candidate_store/policy.json" "$target/input/policy.json"
    chmod 600 "$target/input/"*
    bash "$tools/probot-guest-stage.sh" "$scope" "$target"
    echo "AGNI_PROBOT_GUEST_STAGE=passed candidate=$target activation=blocked"
    ;;
  status)
    [[ $# == 2 ]]
    bash "$tools/runtime.sh" status "$scope"
    echo 'AGNI_PROBOT_GUEST_STATUS=passed'
    ;;
  activate)
    echo 'AGNI_PROBOT_GUEST_ACTIVATION=blocked reason=real-github-app-binding-and-live-ingress-not-qualified' >&2
    exit 1
    ;;
  *) echo 'Usage: verify|stage|status|activate SCOPE [BUNDLE_STORE_PATH]' >&2;exit 2 ;;
esac
