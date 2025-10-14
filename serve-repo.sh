#!/usr/bin/env bash
set -euo pipefail

# Directory paths
WORKDIR=$(pwd)
REPO_DIR="$WORKDIR/builds/latest/x86_64/repo"

# Step 0: Ensure workspace exists
mkdir -p "$WORKDIR/builds/latest/x86_64"

# Step 1: Initialize upstream FCOS config only if missing
if [ ! -d "$WORKDIR/fedora-coreos-config" ]; then
    echo "[+] Initializing Fedora CoreOS upstream config..."
    podman run --privileged --rm -v "$WORKDIR":/srv \
        quay.io/coreos-assembler/coreos-assembler:latest init https://github.com/coreos/fedora-coreos-config
else
    echo "[+] Upstream config exists, skipping init"
fi

# Step 2: Build updated OSTree tree
echo "[+] Building updated OSTree tree..."
podman run --privileged --rm -v "$WORKDIR":/srv \
    quay.io/coreos-assembler/coreos-assembler:latest build

# Step 3: Build minimal BusyBox container to serve the repo
echo "[+] Building OSTree repo container..."
podman stop coreos-repo || true
podman rm coreos-repo || true
podman build -t mycorp/coreos-repo .

# Step 4: Run container
podman run -d --name coreos-repo -p 8080:8080 mycorp/coreos-repo
echo "[✓] OSTree repo available at http://localhost:8080/repo"
