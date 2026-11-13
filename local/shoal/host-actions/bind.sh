#!/usr/bin/env bash
set -Eeuo pipefail

source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ -n "${NIX_XD_SELECTED_PROJECT_REV:-}" ]] || {
  echo 'Run through nix.xd project-host-run with an exact Agni revision' >&2
  exit 2
}
exec python3 "$source_root/binding.py"
