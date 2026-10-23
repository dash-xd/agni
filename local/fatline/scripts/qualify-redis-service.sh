#!/usr/bin/env bash
set -Eeuo pipefail
# Host-side, observational gate for a separately deployed qualification scope.
# Does not create, start, restart, or modify any service.
[[ $# == 3 ]] || { echo "usage: qualify-redis-service.sh EXPECTED_IMAGE_ID EVIDENCE_JSON GENERATED_QUADLET" >&2; exit 2; }
expected="$1"; evidence="$2"; quadlet="$3"
[[ "$expected" =~ ^sha256:[a-f0-9]{64}$ ]] || exit 2
[[ -f "$quadlet" ]] || { echo "Agni-generated Quadlet missing" >&2; exit 1; }
unit="${FATLINE_QUALIFY_UNIT:-}"
container="${FATLINE_QUALIFY_CONTAINER:-}"
conf="${FATLINE_QUALIFY_REDIS_CONF:-}"
[[ "$unit" == fatline-qualify-*.service && "$container" == fatline-qualify-* ]] || {
  echo "Dedicated Smoke-managed qualification unit/container required; refusing production Fatline" >&2
  exit 1
}
[[ -n "$conf" && -f "$conf" ]] || { echo "Agni Redis configuration missing" >&2; exit 1; }
grep -Fxq "ContainerName=$container" "$quadlet" || { echo "Quadlet container identity differs from dedicated test scope" >&2; exit 1; }
for line in 'Network=none' 'ReadOnly=true' 'Pull=never' 'DropCapability=all'; do
  grep -Fxq "$line" "$quadlet" || { echo "Quadlet invariant missing: $line" >&2; exit 1; }
done
for line in 'port 0' 'save ""' 'appendonly no' 'maxmemory 40mb' 'maxmemory-policy noeviction' 'aclfile /etc/redis/users.acl'; do
  grep -Fxq "$line" "$conf" || { echo "Redis invariant missing: $line" >&2; exit 1; }
done
systemctl --user is-active --quiet "$unit" || { echo "Qualification unit not active" >&2; exit 1; }
running="$(podman inspect "$container" --format '{{.Image}}')"
[[ "$running" =~ ^[a-f0-9]{64}$ ]] && running="sha256:$running"
[[ "$running" == "$expected" ]] || { echo "Running image differs from candidate" >&2; exit 1; }
quadlet_sha="$(sha256sum "$quadlet" | cut -d' ' -f1)"
conf_sha="$(sha256sum "$conf" | cut -d' ' -f1)"
jq -cn --arg image_id "$expected" --arg running_image_id "$running" --arg unit "$unit" --arg container "$container" --arg quadlet_sha256 "$quadlet_sha" --arg config_sha256 "$conf_sha" \
  '{schema:1,image_id:$image_id,running_image_id:$running_image_id,unit:$unit,container:$container,quadlet_sha256:$quadlet_sha256,config_sha256:$config_sha256,complete:false}' > "$evidence"
# The Smoke installation/ACL, socket permissions, and restart-recovery probes
# have not been implemented. Observational identity alone is not qualification.
echo "Image, Quadlet and config identity observed; Smoke lifecycle/ACL gates remain unqualified" >&2
exit 1
