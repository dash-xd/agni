#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST="${AGNI_COSA_DIST:-${ROOT}/dist}"

[[ -d "${DIST}" ]] || { echo "missing dist directory: ${DIST}" >&2; exit 1; }

iso_count="$(find "${DIST}" -maxdepth 1 -type f -name '*-live*.iso' | wc -l)"
gcp_count="$(find "${DIST}" -maxdepth 1 -type f -name '*-gcp.*.tar.gz' | wc -l)"
qemu_count="$(find "${DIST}" -maxdepth 1 -type f -name '*.qcow2' | wc -l)"

[[ "${iso_count}" -ge 1 ]] || { echo 'no live ISO artifact found' >&2; exit 1; }
[[ "${gcp_count}" -ge 1 ]] || { echo 'no GCP image archive found' >&2; exit 1; }
[[ "${qemu_count}" -ge 1 ]] || { echo 'no QEMU qcow2 artifact found' >&2; exit 1; }
[[ -s "${DIST}/meta.json" ]] || { echo 'missing COSA meta.json' >&2; exit 1; }
[[ -s "${DIST}/fedora-coreos-config.commit" ]] || { echo 'missing upstream config provenance' >&2; exit 1; }

for archive in "${DIST}"/*-gcp.*.tar.gz; do
  entries="$(tar -tzf "${archive}")"
  [[ "${entries}" == 'disk.raw' || "${entries}" == './disk.raw' ]] || {
    echo "GCP archive must contain only disk.raw: ${archive}" >&2
    printf '%s\n' "${entries}" >&2
    exit 1
  }
done

sha256sum -c "${DIST}/SHA256SUMS"
printf 'Agni CoreOS artifacts passed static verification in %s\n' "${DIST}"
