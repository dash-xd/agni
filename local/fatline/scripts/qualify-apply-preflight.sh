#!/usr/bin/env bash
set -Eeuo pipefail
# Validate the current branch installer without requiring Podman images or
# changing any systemd-user service. Designed for GitHub-hosted preflight.
bash -n local/fatline/scripts/apply-quadlets.sh
bash -n local/fatline/scripts/check-generator.sh
bash -n local/fatline/scripts/check-quadlets.sh
echo "PASS: Agni Fatline installer and generator shell syntax (no deployment)"
