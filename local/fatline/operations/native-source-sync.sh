#!/usr/bin/env bash
set -Eeuo pipefail

[[ "${GHXD_NATIVE_GRANTS_ACK:-}" == TRUST-NIX-ALPINE-OWNER ]] || {
  echo 'AGNI_NATIVE_SOURCE_SYNC=blocked reason=explicit-grant-trust-ack-required' >&2
  exit 2
}
nix_xd="${NIX_XD_DIR:?Specify the v20261115 nix.xd checkout}"
[[ -f "$nix_xd/Makefile" ]] || exit 2
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
checkout="$(basename "$here")"
smoke="${SMOKE_CHECKOUT:-smoke20261115}"
[[ "$checkout" =~ ^[A-Za-z0-9_.-]+$ && "$smoke" =~ ^[A-Za-z0-9_.-]+$ ]] || exit 2
[[ "$here" == "$(cd "$nix_xd/.." && pwd -P)/$checkout" ]] || exit 2
[[ -z "$(git -C "$here" status --porcelain --untracked-files=no)" ]] || {
  echo 'AGNI_NATIVE_SOURCE_SYNC=blocked reason=dirty-source' >&2
  exit 1
}
machine="${MACHINE:-coreos-arm64}"
provider="${PROVIDER:-podman}"
scope="${OWNER_SCOPE:-nix-xd-arm}"
nix_make() {
  make --no-print-directory -C "$nix_xd" "$@" MACHINE="$machine" PROVIDER="$provider" SCOPE="$scope"
}
nix_make stage CHECKOUT="$checkout"
nix_make stage CHECKOUT="$smoke"
manifest="/workspaces/$checkout/local/fatline/qualification/probot-factory-ghxd-sources.json"
log="$(mktemp)"
trap 'rm -f -- "$log"' EXIT
nix_make run FLAKE="$smoke" TARGET='#ghxd-native' ARGS="source-sync $manifest" 2>&1 | tee "$log"
grep -Fxq 'SMOKE_GHXD_NATIVE=passed action=source-sync execution=nix-alpine' "$log" || {
  echo 'AGNI_NATIVE_SOURCE_SYNC=blocked reason=missing-native-success' >&2
  exit 1
}
grep -Fxq 'GHXD_WORKSPACE_SYNC=passed' "$log" || exit 1
echo 'AGNI_NATIVE_SOURCE_SYNC=passed source=smoke-ghxd execution=nix-alpine production=unchanged'
