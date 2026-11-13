#!/usr/bin/env bash
set -Eeuo pipefail
# The selected Agni application owns the VM image, boot profile, and lifecycle.
vmm="${AGNI_VM_VMM:-podman}"
case "$vmm" in
  podman) exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/coreos-podman.sh" stop ;;
  hvf) case "stop" in
    preflight|boot|stop) exec bash "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/coreos-hvf.sh" stop ;;
    *) echo 'Selected profile action requires podman VMM' >&2; exit 2 ;;
    esac ;;
  *) echo 'Unsupported application VM backend' >&2; exit 2 ;;
esac
