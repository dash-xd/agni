#!/usr/bin/env bash
set -euo pipefail

# Pull latest FCOS config
echo "[+] Pulling latest Fedora CoreOS config..."
podman run --privileged --rm -v $(pwd):/srv quay.io/coreos-assembler/coreos-assembler:latest init https://github.com/coreos/fedora-coreos-config

# Build updated tree
echo "[+] Building updated OSTree tree..."
podman run --privileged --rm -v $(pwd):/srv quay.io/coreos-assembler/coreos-assembler:latest build

# Build minimal container serving repo
echo "[+] Building OSTree repo container..."
podman stop coreos-repo || true
podman rm coreos-repo || true
podman build -t mycorp/coreos-repo .

# Run container
podman run -d --name coreos-repo -p 8080:8080 mycorp/coreos-repo
echo "[✓] OSTree repo available at http://localhost:8080/repo"
