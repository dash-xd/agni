#!/usr/bin/env bash
set -euo pipefail

REPO_NAME=mycorp/coreos-repo

echo "[+] Initializing build environment..."
mkdir -p _build
cd _build

if [ ! -d fedora-coreos-config ]; then
  podman run --privileged --rm -v "$(pwd)":/srv \
    quay.io/coreos-assembler/coreos-assembler:latest \
    init https://github.com/coreos/fedora-coreos-config
fi

echo "[+] Copying overrides..."
mkdir -p overrides
cp -r ../overrides overrides/

echo "[+] Building tree..."
podman run --privileged --rm -v "$(pwd)":/srv \
  quay.io/coreos-assembler/coreos-assembler:latest build

echo "[+] Building minimal repo container..."
cp -r builds/latest/x86_64/repo ../repo
cd ..
podman build -t "${REPO_NAME}:latest" .

echo "[+] Running local repo container..."
podman stop coreos-repo || true
podman rm coreos-repo || true
podman run -d --name coreos-repo -p 8080:8080 "${REPO_NAME}:latest"

echo "[✓] Repo available at http://localhost:8080/repo"
