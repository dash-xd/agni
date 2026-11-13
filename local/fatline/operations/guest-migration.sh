#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/output.sh"

# Host-side application workflow. nix.xd remains a generic Nix/SSH transport.
operation=${1:?Choose assess, verify, review or migrate-stage}
deployment=${DEPLOYMENT:-vm1}
nix_xd=${NIX_XD_DIR:-}
provider=${PROVIDER:-podman}
owner_scope=${OWNER_SCOPE:-nix-xd-arm}
machine=${MACHINE:-coreos-arm64}

fail() { printf 'AGNI_DEPLOYMENT=blocked reason=%s\n' "$*" >&2; exit 1; }
case "$deployment" in
  vm1)
    profile_scope=fatline-arm-vm1
    guest_instance=${GUEST_VM_INSTANCE:-starwisp}
    guest_user=${GUEST_SSH_USER:-wisp}
    guest_port=${GUEST_SSH_PORT:-2222}
    ;;
  *) fail "unsupported-deployment:$deployment" ;;
esac
[[ "$provider" == podman || "$provider" == container ]] || fail unsupported-provider
[[ -n "$nix_xd" && -f "$nix_xd/Makefile" ]] || fail missing-nix-xd-directory
nix_xd="$(cd "$nix_xd" && pwd -P)"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
checkout=${AGNI_CHECKOUT:-$(basename "$here")}
[[ "$checkout" =~ ^[A-Za-z0-9_.-]+$ ]] || fail invalid-checkout
[[ "$here" == "$(cd "$nix_xd/.." && pwd -P)/$checkout" ]] || fail workspace-checkout-mismatch
[[ -z "$(git -C "$here" status --porcelain --untracked-files=no)" ]] || fail uncommitted-agni-source
revision="$(git -C "$here" rev-parse HEAD)"
[[ "$revision" =~ ^[a-f0-9]{40}$ ]] || fail invalid-revision
guest_key=${GUEST_SSH_KEY:-"$HOME/.ssh/starwisp-test"}
guest_state=${GUEST_STATE_ROOT:-"$HOME/.local/state/nix-xd/coreos"}
guest_host=${GUEST_SSH_HOST:-127.0.0.1}
flake="$checkout/local/fatline"
log_dir="$(mktemp -d)"
trap 'rm -rf -- "$log_dir"' EXIT

xd_make() {
  make --no-print-directory -C "$nix_xd" "$@" MACHINE="$machine" \
    PROVIDER="$provider" SCOPE="$owner_scope"
}
guest() {
  local mode="$1" bundle="$2" assessment="${3:-}" args
  args="$(python3 - "$mode" "$profile_scope" "$bundle" "$assessment" <<'PY'
import json,sys
items=sys.argv[1:4]
if sys.argv[4]: items.append(sys.argv[4])
print(json.dumps(items,separators=(',',':')))
PY
)"
  xd_make guest-app FLAKE="$flake" TARGET='#vm1-probot-guest-stage' \
    GUEST_APP_REV="$revision" ARGS_JSON="$args" \
    GUEST_VM_INSTANCE="$guest_instance" GUEST_STATE_ROOT="$guest_state" \
    GUEST_SSH_USER="$guest_user" GUEST_SSH_PORT="$guest_port" \
    GUEST_SSH_HOST="$guest_host" GUEST_SSH_KEY="$guest_key"
}
run_step() {
  local output="$1";shift
  "$@" | tee "$output"
}

[[ "$operation" == assess || "$operation" == verify || "$operation" == review || "$operation" == migrate-stage ]] || fail unsupported-operation
echo "AGNI_DEPLOYMENT_SELECTED=passed deployment=$deployment scope=$profile_scope operation=$operation source=$revision"
xd_make stage CHECKOUT="$checkout" | tee "$log_dir/stage.log"
grep -Fq "Staged $checkout at $revision" "$log_dir/stage.log" || fail staged-source-not-pinned

run_step "$log_dir/bundle.log" xd_make qualify QUALIFY_APP=1 FLAKE="$flake" \
  TARGET='#qualify-integration' ARGS='--scenario probot-webhook --phase guest-bundle'
grep -Fxq 'AGNI_PROBOT_GUEST_BUNDLE=passed roles=3 credentials=excluded activation=blocked' "$log_dir/bundle.log" || fail bundle-not-qualified
bundle="$(agni_capture_value AGNI_PROBOT_GUEST_BUNDLE_PATH "$log_dir/bundle.log")"
[[ "$bundle" =~ ^/nix/store/[a-z0-9]{32}-candidate$ ]] || fail invalid-qualified-bundle

if [[ "$operation" == verify ]]; then
  run_step "$log_dir/verify.log" guest verify "$bundle"
  grep -Fxq 'AGNI_PROBOT_GUEST_VERIFY=passed activation=blocked' "$log_dir/verify.log" || fail guest-verification-not-qualified
  echo "AGNI_DEPLOYMENT=passed deployment=$deployment operation=verify activation=blocked"
  exit 0
fi

run_step "$log_dir/assess.log" guest adopt-plan "$bundle"
grep -Fq 'AGNI_PROBOT_ADOPTION_ASSESSMENT=passed ' "$log_dir/assess.log" || fail adoption-assessment-not-qualified
assessment_path="$(agni_capture_value AGNI_PROBOT_ADOPTION_ASSESSMENT_PATH "$log_dir/assess.log")"
[[ "$assessment_path" =~ /([0-9a-f]{64})\.json$ ]] || fail invalid-assessment-evidence
assessment="${BASH_REMATCH[1]}"
if [[ "$operation" == assess ]]; then
  echo "AGNI_DEPLOYMENT=passed deployment=$deployment operation=assess activation=blocked"
  exit 0
fi
run_step "$log_dir/review.log" guest adopt-review "$bundle" "$assessment"
grep -Fq 'AGNI_PROBOT_ADOPTION_REVIEW=passed ' "$log_dir/review.log" || fail adoption-review-not-qualified
if [[ "$operation" == review ]]; then
  echo "AGNI_DEPLOYMENT=passed deployment=$deployment operation=review activation=blocked"
  exit 0
fi

run_step "$log_dir/migrate.log" guest adopt-stage "$bundle" "$assessment"
grep -Fq 'AGNI_PROBOT_MIGRATION_STAGE=passed roles=5 ' "$log_dir/migrate.log" || fail migration-stage-not-qualified
echo "AGNI_DEPLOYMENT=passed deployment=$deployment operation=migrate-stage activation=blocked"
