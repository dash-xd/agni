#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="${AGNI_COSA_WORKDIR:-${ROOT}/work}"
DIST="${AGNI_COSA_DIST:-${ROOT}/dist}"
TARGET="${1:-all}"

# shellcheck disable=SC1091
source "${ROOT}/config.env"

cosa() {
  podman run --rm --security-opt=label=disable --privileged \
    --userns=keep-id:uid=1000,gid=1000 \
    -v "${WORK}:/srv" \
    --device=/dev/kvm \
    --device=/dev/fuse \
    --tmpfs=/tmp \
    -v /var/tmp:/var/tmp \
    "${COSA_IMAGE}" "$@"
}

require_devices() {
  [[ -c /dev/kvm ]] || { echo '/dev/kvm is required for COSA image builds' >&2; exit 1; }
  [[ -c /dev/fuse ]] || { echo '/dev/fuse is required for COSA image builds' >&2; exit 1; }
}

prepare() {
  "${ROOT}/prepare-config.sh"
}

compose() {
  require_devices
  [[ -d "${WORK}/src/config" ]] || prepare
  cosa fetch
  cosa build
}

osbuild() {
  local platform="$1"
  require_devices
  [[ -L "${WORK}/builds/latest" || -d "${WORK}/builds/latest" ]] || compose
  cosa osbuild "${platform}"
}

collect() {
  mkdir -p "${DIST}"
  find "${WORK}/builds" -type f \( \
      -name '*-live*.iso' -o \
      -name '*-gcp.*.tar.gz' -o \
      -name '*.qcow2' \
    \) -exec cp -f {} "${DIST}/" \;

  cp -f "${WORK}/builds/latest/meta.json" "${DIST}/meta.json"
  git -C "${WORK}/src/config" rev-parse HEAD > "${DIST}/fedora-coreos-config.commit"
  sha256sum "${DIST}"/* > "${DIST}/SHA256SUMS"
}

case "${TARGET}" in
  prepare)
    prepare
    ;;
  compose)
    prepare
    compose
    collect
    ;;
  qemu)
    prepare
    compose
    osbuild qemu
    collect
    ;;
  iso)
    prepare
    compose
    osbuild live
    collect
    ;;
  gcp)
    prepare
    compose
    osbuild gcp
    collect
    ;;
  all)
    prepare
    compose
    osbuild qemu
    osbuild live
    osbuild gcp
    collect
    "${ROOT}/verify.sh"
    ;;
  *)
    echo "usage: $0 {prepare|compose|qemu|iso|gcp|all}" >&2
    exit 2
    ;;
esac
