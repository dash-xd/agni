#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="${AGNI_COSA_WORKDIR:-${ROOT}/work}"

# shellcheck disable=SC1091
source "${ROOT}/config.env"

rm -rf "${WORK}"
mkdir -p "${WORK}"

git clone --filter=blob:none "${FCOS_CONFIG_URL}" "${WORK}/src/config"
git -C "${WORK}/src/config" checkout --detach "${FCOS_CONFIG_REF}"

while IFS= read -r item; do
  [[ -z "${item}" || "${item}" == \#* ]] && continue

  # Remove exact YAML list entries while allowing trailing comments. We edit only
  # the disposable pinned upstream checkout, never the source list in Agni.
  escaped="$(printf '%s' "${item}" | sed 's/[][\\.^$*+?{}|()]/\\&/g')"
  while IFS= read -r -d '' yaml; do
    sed -i -E "/^[[:space:]]*-[[:space:]]+${escaped}([[:space:]]*(#.*)?)?$/d" "${yaml}"
  done < <(find "${WORK}/src/config" -type f \( -name '*.yaml' -o -name '*.yml' \) -print0)
done < "${ROOT}/remove-manifest-items.txt"

mv "${WORK}/src/config/manifest.yaml" "${WORK}/src/config/manifest.upstream.yaml"

{
  printf '%s\n' 'include:'
  printf '%s\n' '  - manifest.upstream.yaml'
  printf '%s\n' '  - agni-production.yaml'
} > "${WORK}/src/config/manifest.yaml"

{
  printf '%s\n' 'exclude-packages:'
  while IFS= read -r package; do
    [[ -z "${package}" || "${package}" == \#* ]] && continue
    printf '  - %s\n' "${package}"
  done < "${ROOT}/exclude-packages.txt"
} > "${WORK}/src/config/agni-production.yaml"

mkdir -p "${WORK}/src/config/overlay.d"
cp -a "${ROOT}/overlay.d/." "${WORK}/src/config/overlay.d/"

printf 'Prepared Agni CoreOS config from %s at %s\n' "${FCOS_CONFIG_URL}" "${FCOS_CONFIG_REF}"
printf 'Work directory: %s\n' "${WORK}"
