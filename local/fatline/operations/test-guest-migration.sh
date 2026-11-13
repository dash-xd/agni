#!/usr/bin/env bash
set -Eeuo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
bash -n "$here/operations/guest-migration.sh"
output="$(make --no-print-directory -C "$here" help)"
for operation in assess verify review migrate-stage; do
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
echo 'AGNI_DEPLOYMENT_INTERFACE_TEST=passed named-operations=true json=transport-only'
