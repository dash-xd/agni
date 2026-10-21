#!/usr/bin/env bash
set -euo pipefail

# Run on the intended systemd/Podman host. This does not install or start units.
base="$(cd "$(dirname "${BASH_SOURCE[0]}")/../systemd" && pwd)"
generator=""
for candidate in   /usr/lib/systemd/system-generators/podman-system-generator   /usr/libexec/systemd/system-generators/podman-system-generator   /usr/local/lib/systemd/system-generators/podman-system-generator; do
  if [[ -x "$candidate" ]]; then generator="$candidate"; break; fi
done
if [[ -z "$generator" ]]; then
  echo "Quadlet generator not found on this host; cannot qualify generated services" >&2
  exit 1
fi
command -v podman >/dev/null || { echo "podman unavailable on host" >&2; exit 1; }
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# Use only the source candidate units, never the installed host units.
for file in "$base"/*.container; do cp "$file" "$tmp/"; done
output="$(QUADLET_UNIT_DIRS="$tmp" "$generator" --dryrun 2>&1)" || {
  printf '%s\n' "$output" >&2
  exit 1
}
printf '%s\n' "$output"
for name in fatline-redis fatline-logma fatline-skymill; do
  if ! grep -Fq "$name.service" <<<"$output"; then
    echo "Generator output did not establish $name.service" >&2
    exit 1
  fi
done
echo "Fatline Quadlet generator PASS (services not installed or started)"
