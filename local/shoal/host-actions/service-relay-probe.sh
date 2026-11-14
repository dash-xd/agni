#!/usr/bin/env bash
set -Eeuo pipefail
source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ "${NIX_XD_PROJECT_REV:-}" =~ ^[a-f0-9]{40}$ &&
   "${NIX_XD_PROJECT_REV:-}" == "${NIX_XD_SELECTED_PROJECT_REV:-}" ]] || {
  echo 'Service relay requires exact Agni source revision' >&2
  exit 2
}
exec python3 "$source_root/service_relay.py"
