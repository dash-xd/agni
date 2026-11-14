#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export SHOAL_HOSTKEY_ACTION=enroll
exec python3 "$root/hostkey.py"
