#!/usr/bin/env bash
set -Eeuo pipefail
scope=${1:?scope}
[[ "$scope" =~ ^[a-z][a-z0-9-]{0,31}$ ]]
deadline=$((SECONDS + 180))
while (( SECONDS < deadline )); do
  if [[ $(findmnt -rn -o FSTYPE --mountpoint /var/mnt/nixstore || true) == 9p &&
        ",$(findmnt -rn -o OPTIONS --mountpoint /var/mnt/nixstore || true)," == *,ro,* ]]; then
    for executable in "$@"; do
      [[ "$executable" == "$scope" ]] && continue
      [[ "$executable" =~ ^/nix/store/[a-z0-9]{32}-[^/]+/ ]] || exit 1
      test -r "/var/mnt/nixstore/${executable#/nix/store/}"
    done
    echo FATLINE_BOOT_STORE_READY=passed
    exit 0
  fi
  sleep 2
done
echo 'Read-only 9P store did not become ready within 180 seconds' >&2
exit 1
