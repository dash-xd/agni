#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

action=${1:?Select adopt-plan, adopt-review, adopt-stage, migrate-verify, verify, stage, status or activate}
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
  adopt-plan)
    [[ $# == 3 ]]
    check_bundle
    [[ -d "$apps/rootfs" && -x "$apps/rootfs/bin/busybox" ]] || {
      echo 'AGNI_PROBOT_ADOPTION_ASSESSMENT=blocked reason=guest-rootfs-missing' >&2
      exit 1
    }
    active_roles=()
    for role in redis nginx logma skymill probot; do
      if systemctl --user is-active --quiet "$scope-$role.service"; then
        active_roles+=("$role")
      fi
    done
    [[ " ${active_roles[*]} " == *" redis "* ]] || {
      echo 'AGNI_PROBOT_ADOPTION_ASSESSMENT=blocked reason=redis-not-active' >&2
      exit 1
    }
    active="$(IFS=,; echo "${active_roles[*]}")"
    python="$(sed -n '1p' "$tools/python-path")"
    [[ "$python" == /nix/store/*/bin/python3 ]] || exit 1
    evidence="$apps/adoption-assessments"
    mkdir -p -m 700 "$evidence"
    podman run --rm --pull=never --network none \
      --userns keep-id:uid=1000,gid=1000 --user 1000:1000 \
      --read-only --read-only-tmpfs=false --security-opt label=disable \
      --cap-drop all --security-opt no-new-privileges \
      --mount type=bind,src=/var/mnt/nixstore,dst=/nix/store,ro \
      --mount "type=bind,src=$base,dst=/run/base,ro" \
      --mount "type=bind,src=$HOME/.config/containers/systemd,dst=/run/units,ro" \
      --mount "type=bind,src=$evidence,dst=/run/evidence,rw" \
      --tmpfs /tmp:rw,nosuid,nodev,size=4m \
      --rootfs "$apps/rootfs" "$python" "$tool_store/probot-adoption.py" \
      --scope "$scope" --base /run/base --units /run/units \
      --output-dir /run/evidence --display-dir "$evidence" \
      --bundle "$bundle_store" --active-roles "$active"
    ;;
  adopt-review)
    [[ $# == 4 ]]
    check_bundle
    evidence="$apps/adoption-assessments"
    digest="$4"
    [[ "$digest" =~ ^[0-9a-f]{64}$ && -f "$evidence/$digest.json" && ! -L "$evidence/$digest.json" ]] || {
      echo 'AGNI_PROBOT_ADOPTION_REVIEW=blocked reason=missing-immutable-evidence' >&2
      exit 1
    }
    [[ -d "$apps/rootfs" && -x "$apps/rootfs/bin/busybox" ]] || exit 1
    python="$(sed -n '1p' "$tools/python-path")"
    [[ "$python" == /nix/store/*/bin/python3 ]] || exit 1
    podman run --rm --pull=never --network none \
      --userns keep-id:uid=1000,gid=1000 --user 1000:1000 \
      --read-only --read-only-tmpfs=false --security-opt label=disable \
      --cap-drop all --security-opt no-new-privileges \
      --mount type=bind,src=/var/mnt/nixstore,dst=/nix/store,ro \
      --mount "type=bind,src=$evidence,dst=/run/evidence,ro" \
      --mount "type=bind,src=$candidate_store,dst=/run/candidate,ro" \
      --tmpfs /tmp:rw,nosuid,nodev,size=4m \
      --rootfs "$apps/rootfs" "$python" "$tool_store/probot-adoption-review.py" \
      --assessment "/run/evidence/$digest.json" --bundle /run/candidate \
      --bundle-store "$bundle_store"
    ;;
  adopt-stage)
    [[ $# == 4 ]]
    check_bundle
    digest="$4"
    evidence="$apps/adoption-assessments"
    [[ "$digest" =~ ^[0-9a-f]{64}$ && -f "$evidence/$digest.json" && ! -L "$evidence/$digest.json" ]] || {
      echo 'AGNI_PROBOT_MIGRATION_STAGE=blocked reason=missing-immutable-assessment' >&2
      exit 1
    }
    [[ -d "$apps/rootfs" && -x "$apps/rootfs/bin/busybox" ]] || {
      echo 'AGNI_PROBOT_MIGRATION_STAGE=blocked reason=legacy-rootfs-missing' >&2
      exit 1
    }
    for role in redis nginx logma skymill; do
      systemctl --user is-active --quiet "$scope-$role.service" || {
        echo "AGNI_PROBOT_MIGRATION_STAGE=blocked reason=legacy-service-not-active role=$role" >&2
        exit 1
      }
    done
    for role in logma skymill bootstrap; do
      [[ -s "$apps/credentials/$role/redis" ]] || exit 1
    done
    [[ -s "$apps/credentials/logma/api-key" ]] || exit 1
    [[ ! -e "$apps/profile/profile.env" && ! -e "$apps/profile/manifest.json" ]] || {
      echo 'AGNI_PROBOT_MIGRATION_STAGE=blocked reason=consolidated-profile-already-exists' >&2
      exit 1
    }
    python="$(sed -n '1p' "$tools/python-path")"
    [[ "$python" == /nix/store/*/bin/python3 ]] || exit 1
    target="$apps/probot-migrations/$digest-${bundle_store##*/}"
    [[ ! -e "$target" ]] || {
      echo 'AGNI_PROBOT_MIGRATION_STAGE=blocked reason=incomplete-private-generation' >&2
      exit 1
    }
    mkdir -m 700 -p "$apps/probot-migrations"
    exec 9>"$base/lifecycle.lock"
    flock -x 9
    podman run --rm --pull=never --network none \
      --userns keep-id:uid=1000,gid=1000 --user 1000:1000 \
      --read-only --read-only-tmpfs=false --security-opt label=disable \
      --cap-drop all --security-opt no-new-privileges \
      --mount type=bind,src=/var/mnt/nixstore,dst=/nix/store,ro \
      --mount "type=bind,src=$base/credentials/users.acl,dst=/run/old-acl,ro" \
      --mount "type=bind,src=$apps/credentials,dst=/run/old-credentials,ro" \
      --mount "type=bind,src=$HOME/.config/containers/systemd,dst=/run/units,ro" \
      --mount "type=bind,src=$evidence,dst=/run/evidence,ro" \
      --mount "type=bind,src=$apps/probot-migrations,dst=/run/migrations,rw" \
      --tmpfs /tmp:rw,nosuid,nodev,size=4m \
      --rootfs "$apps/rootfs" "$python" "$tool_store/probot-migrate.py" \
      --assessment "/run/evidence/$digest.json" \
      --unit-dir /run/units --acl /run/old-acl --credentials /run/old-credentials \
      --metadata "$tool_store/metadata.json" \
      --paths "$tool_store/migration-paths.json" \
      --bundle-store "$bundle_store" --candidate "$bundle_store" \
      --home "$HOME" --output "/run/migrations/$digest-${bundle_store##*/}" \
      --display-dir "$apps/probot-migrations" \
      --acl-renderer "$tool_store/render-users-acl.py" \
      --credential-generator "$tool_store/probot-credentials.py" \
      --profile-renderer "$tool_store/probot-render.py" \
      --base-renderer "$tool_store/render.py" \
      --stage-helper "$tool_store/probot-stage.py"
    ;;
  migrate-verify)
    [[ $# == 2 ]]
    [[ -d "$apps/rootfs" && -x "$apps/rootfs/bin/busybox" ]] || exit 1
    candidates=()
    shopt -s nullglob
    for path in "$apps/probot-migrations/"*; do
      [[ -d "$path" && ! -L "$path" ]] || exit 1
      candidates+=("$path")
    done
    shopt -u nullglob
    [[ "${#candidates[@]}" == 1 ]] || {
      echo 'AGNI_PROBOT_MIGRATION_VERIFY=blocked reason=ambiguous-or-missing-generation' >&2
      exit 1
    }
    target="${candidates[0]}"
    basename="${target##*/}"
    [[ "$basename" =~ ^([0-9a-f]{64})-([0-9a-z]{32}-candidate)$ ]] || exit 1
    digest="${BASH_REMATCH[1]}"
    bundle_store="/nix/store/${BASH_REMATCH[2]}"
    check_bundle
    evidence="$apps/adoption-assessments/$digest.json"
    [[ -s "$evidence" && ! -L "$evidence" ]] || exit 1
    [[ -s "$target/rendered/profile.env" && -s "$target/rendered/manifest.json" ]] || exit 1
    python="$(sed -n '1p' "$tools/python-path")"
    [[ "$python" == /nix/store/*/bin/python3 ]] || exit 1
    before=()
    for role in redis nginx logma skymill; do
      systemctl --user is-active --quiet "$scope-$role.service" || exit 1
      before+=("$(systemctl --user show "$scope-$role.service" -p InvocationID --value)")
      [[ -n "${before[${#before[@]}-1]}" ]] || exit 1
    done
    podman run --rm --pull=never --network none \
      --userns keep-id:uid=1000,gid=1000 --user 1000:1000 \
      --read-only --read-only-tmpfs=false --security-opt label=disable \
      --cap-drop all --security-opt no-new-privileges \
      --mount type=bind,src=/var/mnt/nixstore,dst=/nix/store,ro \
      --mount "type=bind,src=$target,dst=/run/migration,ro" \
      --mount "type=bind,src=$evidence,dst=/run/assessment.json,ro" \
      --mount "type=bind,src=$base/credentials/users.acl,dst=/run/old-acl,ro" \
      --mount "type=bind,src=$HOME/.config/containers/systemd,dst=/run/units,ro" \
      --tmpfs /tmp:rw,nosuid,nodev,size=4m \
      --rootfs "$apps/rootfs" "$python" "$tool_store/probot-migration-verify.py" \
      --migration /run/migration --assessment /run/assessment.json \
      --generation "$basename" \
      --old-acl /run/old-acl --installed-units /run/units --store /nix/store
    generator=/usr/lib/systemd/system-generators/podman-system-generator
    [[ -x "$generator" ]] || {
      echo 'AGNI_PROBOT_MIGRATION_VERIFY=blocked reason=quadlet-generator-not-found' >&2
      exit 1
    }
    quadlet_output="$(mktemp)"
    trap 'rm -f "$quadlet_output"' EXIT
    QUADLET_UNIT_DIRS="$target/rendered" "$generator" --user --dryrun > "$quadlet_output"
    for role in redis nginx logma skymill probot; do
      grep -Fq "$scope-$role.service" "$quadlet_output" || {
        echo "AGNI_PROBOT_MIGRATION_VERIFY=blocked reason=quadlet-not-generated role=$role" >&2
        exit 1
      }
    done
    echo 'AGNI_PROBOT_QUADLET_GENERATOR=passed roles=5 dryrun=true installed=unchanged'
    after=()
    for role in redis nginx logma skymill; do
      systemctl --user is-active --quiet "$scope-$role.service" || exit 1
      after+=("$(systemctl --user show "$scope-$role.service" -p InvocationID --value)")
    done
    [[ "${before[*]}" == "${after[*]}" ]] || {
      echo 'AGNI_PROBOT_MIGRATION_VERIFY=blocked reason=live-service-invocation-changed' >&2
      exit 1
    }
    echo "AGNI_PROBOT_MIGRATION_VERIFY=passed roles=5 candidate=$target activation=blocked redis_restart=none"
    ;;
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
  *) echo 'Usage: adopt-plan|adopt-review|adopt-stage|migrate-verify|verify|stage|status|activate SCOPE [BUNDLE_STORE_PATH]' >&2;exit 2 ;;
esac
