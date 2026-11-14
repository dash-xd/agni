#!/usr/bin/env bash
set -Eeuo pipefail
source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ "${NIX_XD_PROJECT_REV:-}" =~ ^[0-9a-f]{40}$ &&
   "${NIX_XD_PROJECT_REV:-}" == "${NIX_XD_SELECTED_PROJECT_REV:-}" ]] || {
  echo 'Backup verification requires exact Agni revision' >&2
  exit 2
}
exec python3 "$source_root/backup_verify.py"
