#!/usr/bin/env bash
set -Eeuo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/store-selection.sh"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
printf 'runner=sha256:fixture\nshared_nix_volume=nix-xd-arm-store\n' > "$temp/build.txt"
unset COREOS_NIX_STORE_VOLUME || true
[[ "$(agni_vm_select_store_volume "$temp/build.txt")" == nix-xd-arm-store ]]
COREOS_NIX_STORE_VOLUME= 
[[ "$(agni_vm_select_store_volume "$temp/build.txt")" == nix-xd-arm-store ]]
COREOS_NIX_STORE_VOLUME=nix-xd-arm-store
[[ "$(agni_vm_select_store_volume "$temp/build.txt")" == nix-xd-arm-store ]]
COREOS_NIX_STORE_VOLUME=other-store
[[ "$(agni_vm_select_store_volume "$temp/build.txt")" == other-store ]]
COREOS_NIX_STORE_VOLUME= 
printf 'runner=sha256:fixture\nshared_nix_volume=none\n' > "$temp/build.txt"
[[ -z "$(agni_vm_select_store_volume "$temp/build.txt")" ]]
printf 'shared_nix_volume=a\nshared_nix_volume=b\n' > "$temp/build.txt"
if agni_vm_select_store_volume "$temp/build.txt" >/dev/null 2>&1; then
  echo 'Duplicate build manifest store fields were accepted' >&2
  exit 1
fi
echo AGNI_VM_STORE_SELECTION_CONTRACT=passed
