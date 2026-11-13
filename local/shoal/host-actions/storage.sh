#!/usr/bin/env bash
set -Eeuo pipefail
source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ "${NIX_XD_PROJECT_REV:-}" =~ ^[0-9a-f]{40}$ && \
   "${NIX_XD_PROJECT_REV:-}" == "${NIX_XD_SELECTED_PROJECT_REV:-}" ]] || {
  echo 'Storage qualifier requires a selected exact Agni PROJECT_REV' >&2
  exit 2
}
exec python3 "$source_root/storage.py"
