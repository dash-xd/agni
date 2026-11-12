#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

scope=${1:?scope}
candidate=${2:?candidate}
[[ "$scope" == fatline-arm-vm1 && $(id -u) -ne 0 ]]
base="$HOME/.local/state/nix-xd/fatline/$scope"
apps="$base/services"
[[ "$candidate" == "$apps/probot-candidates/"* && "$candidate" != *..* ]] || {
  echo 'Candidate path outside scoped application state' >&2
  exit 2
}
[[ "$(findmnt -rn -o FSTYPE --mountpoint /var/mnt/nixstore)" == 9p ]]
[[ ",$(findmnt -rn -o OPTIONS --mountpoint /var/mnt/nixstore)," == *,ro,* ]]
[[ "$(podman info --format '{{.Host.Security.Rootless}}')" == true ]]
[[ -s "$base/credentials/users.acl" && -d "$apps/credentials" ]]
for name in spec artifacts sources policy; do
  [[ -s "$candidate/input/$name.json" ]] || {
    echo "Missing staged candidate input: $name" >&2
    exit 2
  }
done

bundle="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
[[ "$bundle" == /var/mnt/nixstore/* && "$bundle" != *..* ]]
python="$(cat "$bundle/python-path")"
[[ "$python" == /nix/store/*/bin/python3 ]]
store_bundle="/nix/store/${bundle##*/}"
[[ ! -e "$candidate/rendered" ]] || {
  echo 'Candidate generation exists; choose a new staged directory' >&2
  exit 1
}
podman run --rm --pull=never --network none --name "$scope-probot-staging" \
  --userns keep-id:uid=1000,gid=1000 --user 1000:1000 \
  --read-only --read-only-tmpfs=false --security-opt label=disable \
  --cap-drop all --security-opt no-new-privileges \
  --mount type=bind,src=/var/mnt/nixstore,dst=/nix/store,ro \
  --mount "type=bind,src=$candidate,dst=/run/candidate,rw" \
  --mount "type=bind,src=$base/credentials/users.acl,dst=/run/old-acl,ro" \
  --mount "type=bind,src=$apps/credentials,dst=/run/old-credentials,ro" \
  --tmpfs /tmp:rw,nosuid,nodev,size=4m \
  --rootfs "$apps/rootfs" \
  "$python" "$store_bundle/probot-stage.py" \
    --spec /run/candidate/input/spec.json \
    --artifacts /run/candidate/input/artifacts.json \
    --sources /run/candidate/input/sources.json \
    --policy /run/candidate/input/policy.json \
    --old-acl /run/old-acl \
    --old-credentials /run/old-credentials \
    --output /run/candidate/rendered \
    --acl-renderer "$store_bundle/render-users-acl.py" \
    --credential-generator "$store_bundle/probot-credentials.py" \
    --profile-renderer "$store_bundle/probot-render.py" \
    --base-renderer "$store_bundle/render.py"

[[ -s "$candidate/rendered/users.acl" &&
   -s "$candidate/rendered/profile.env" &&
   -s "$candidate/rendered/$scope-probot.container" ]]
echo 'FATLINE_PROBOT_VM1_STAGE=passed activation=blocked'
