#!/usr/bin/env bash
set -Eeuo pipefail

: "${NIX_XD_RUNTIME_REPO:?Nix-Alpine host runtime required}"
: "${NIX_XD_COMPOSITION_FLAKE:?Select the active composition flake}"
: "${NIX_XD_COMPOSITION_REV:?Pin the active composition revision}"
: "${NIX_XD_SELECTED_PROJECT_REV:?Project source revision required}"

# Compatibility adapter: the application-specific Python controller moves to
# Agni after the running VM's resource gate qualifies.
export NIX_XD_ARTIFACT_FLAKE="${NIX_XD_ARTIFACT_FLAKE:-github:dash-xd/agni/1b66448cf3ba453767ac6b2b4aaf61337224a7c8?dir=local/fatline}"
export WISP_SMOKE_REV=66950da9a5e4e5303f5dcd018f9039f9b6fc8496
exec python3 "$NIX_XD_RUNTIME_REPO/lib/fatline_logmash.py" --resource
