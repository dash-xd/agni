#!/usr/bin/env bash
set -Eeuo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
bash -n "$here/operations/guest-migration.sh"
bash -n "$here/operations/output.sh"
source "$here/operations/output.sh"
capture_fixture="$(mktemp)"
trap 'rm -f "$capture_fixture"' EXIT
printf '%s\n' 'NOISE=other' 'AGNI_PROBOT_GUEST_BUNDLE_PATH=/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-candidate' > "$capture_fixture"
[[ "$(agni_capture_value AGNI_PROBOT_GUEST_BUNDLE_PATH "$capture_fixture")" == /nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-candidate ]]
if agni_capture_value MISSING "$capture_fixture" >/dev/null; then
  echo 'Accepted missing output field' >&2
  exit 1
fi
printf '%s\n' 'AGNI_PROBOT_GUEST_BUNDLE_PATH=/nix/store/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-candidate' >> "$capture_fixture"
if agni_capture_value AGNI_PROBOT_GUEST_BUNDLE_PATH "$capture_fixture" >/dev/null; then
  echo 'Accepted duplicate output field' >&2
  exit 1
fi
printf '%s\n' 'FIELD=' > "$capture_fixture"
if agni_capture_value FIELD "$capture_fixture" >/dev/null; then
  echo 'Accepted empty output field' >&2
  exit 1
fi
output="$(make --no-print-directory -C "$here" help)"
for operation in assess verify review migrate-stage migrate-verify migrate-activation-plan migrate-activation-check migrate-activate; do
  grep -Fq "deployment-$operation" <<< "$output"
  make -s -n -C "$here" "deployment-$operation" >/dev/null
done
# Operator-facing Make targets must use named operations, not manual JSON or store hashes.
! grep -Eq 'ARGS_JSON|/nix/store/[a-z0-9]{32}-candidate' "$here/Makefile"
# Unsupported deployment fails before network, staging, Nix or SSH.
set +e
bad="$(DEPLOYMENT=unsupported NIX_XD_DIR=/nonexistent bash "$here/operations/guest-migration.sh" migrate-stage 2>&1)"
status=$?
set -e
[[ $status != 0 && "$bad" == *'unsupported-deployment'* ]]
# The activation target must reject even if the user tries to invoke it directly.
set +e
blocked="$(make --no-print-directory -s -C "$here" deployment-migrate-activate DEPLOYMENT=vm1 2>&1)"
status=$?
set -e
[[ $status != 0 && "$blocked" == *'AGNI_ACTIVATION=blocked'* ]]
echo 'AGNI_DEPLOYMENT_INTERFACE_TEST=passed named-operations=true json=transport-only bash32-compatible=true'
