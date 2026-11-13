#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SHOAL_WORLD1_ACTION=preflight
exec python3 "$root/world1.py"
