#!/usr/bin/env bash
set -Eeuo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
temp="$(mktemp -d)"
trap 'rm -rf "$temp"' EXIT
export HOME="$temp/home"
mkdir -p "$HOME/.local/state/nix-xd/fatline/fatline-arm-vm1/services" "$HOME/.config/containers/systemd" "$temp/bin"
base="$HOME/.local/state/nix-xd/fatline/fatline-arm-vm1"
mkdir -p "$base/credentials" "$base/config"
printf 'user default off\nuser publisher on\nuser subscriber on\n' > "$base/credentials/users.acl"
printf 'save ""\n' > "$base/config/redis.conf"
cat > "$temp/bin/id" <<'SH'
#!/bin/sh
echo 1000
SH
cat > "$temp/bin/podman" <<'SH'
#!/bin/sh
echo true
SH
cat > "$temp/bin/findmnt" <<'SH'
#!/bin/sh
case "$*" in *FSTYPE*) echo 9p ;; *OPTIONS*) echo ro,nosuid ;; *) exit 1 ;; esac
SH
cat > "$temp/bin/systemctl" <<'SH'
#!/bin/sh
exit 0
SH
chmod +x "$temp/bin/"*
export PATH="$temp/bin:$PATH"
out="$(bash "$root/coreos-services/vm1-check.sh" inventory fatline-arm-vm1)"
grep -Fxq 'AGNI_VM1_RUNTIME_INVENTORY=passed profile=absent redis=active application_units=0' <<< "$out"
if bash "$root/coreos-services/vm1-check.sh" store-check fatline-arm-vm1 >/dev/null 2>&1; then
  echo 'Guest store qualifier accepted missing immutable paths' >&2
  exit 1
fi
echo AGNI_VM1_GUEST_CONTRACT=passed
