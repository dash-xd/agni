#!/usr/bin/env bash
set -Eeuo pipefail
[[ $# == 5 ]] || { echo "usage: reconcile-redis.sh LOGMA_IMAGE REDIS_IMAGE SCOPE CREDENTIAL_DIR SOCKET_DIR" >&2; exit 2; }
logma_image=$1 redis_image=$2 scope=$3 credential_dir=$4 socket_dir=$5
bootstrap_password=$(<"$credential_dir/bootstrap")
logma_password=$(<"$credential_dir/logma")
api_key=$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')
[[ ${#bootstrap_password} -ge 32 && ${#logma_password} -ge 32 && ${#api_key} -ge 32 ]] || {
  echo "Redis bootstrap and Logma credentials must be provisioned before reconciliation" >&2
  exit 1
}
name="fatline-reconcile-$$"
podman rm -f "$name" >/dev/null 2>&1 || true
cleanup() { podman rm -f "$name" >/dev/null 2>&1 || true; }
trap cleanup EXIT
podman run -d --name "$name" --network none --read-only --user 65534:65534 \
  --cap-drop ALL --security-opt no-new-privileges \
  -v "$socket_dir:/run/redis" \
  --mount type=tmpfs,destination=/var/lib/logma/lifecycle,tmpfs-size=4194304,tmpfs-mode=1777 \
  -e REDIS_NETWORK=unix -e REDIS_URI=/run/redis/redis.sock -e REDIS_SOCKET=/run/redis/redis.sock \
  -e REDIS_USERNAME=bootstrap -e REDISCLI_AUTH="$bootstrap_password" \
  -e FATLINE_SCOPE="$scope" -e LOGMA_RATELIMITER_BOOTSTRAP=internal \
  -e API_KEY="$api_key" "$logma_image" >/dev/null
cli() {
  podman run --rm --network none --read-only --user 65534:65534 \
    --cap-drop ALL --security-opt no-new-privileges \
    -v "$socket_dir:/run/redis" \
    --entrypoint redis-cli "$redis_image" -s /run/redis/redis.sock \
    --user bootstrap -a "$bootstrap_password" --no-auth-warning "$@"
}
ready=0
for _ in $(seq 1 120); do
  if cli FUNCTION LIST 2>/dev/null | grep -Fq dashxd_ratelimit; then ready=1; break; fi
  if [[ "$(podman inspect "$name" --format '{{.State.Running}}' 2>/dev/null || true)" != true ]]; then break; fi
  sleep .25
done
[[ $ready == 1 ]] || { podman logs "$name" >&2 || true; echo "Logma failed to install Ratelimiter Functions" >&2; exit 1; }
podman rm -f "$name" >/dev/null
[[ "$(cli ACL SETUSER bootstrap off)" == OK ]] || { echo "Could not revoke bootstrap Redis identity" >&2; exit 1; }
disabled=$(cli PING 2>&1 || true)
[[ "$disabled" == *WRONGPASS* ]] || { echo "Bootstrap identity still authenticates after revocation" >&2; exit 1; }
logma_result=$(podman run --rm --network none --read-only --user 65534:65534 \
  --cap-drop ALL --security-opt no-new-privileges \
  -v "$socket_dir:/run/redis" \
  --entrypoint redis-cli "$redis_image" -s /run/redis/redis.sock \
  --user logma -a "$logma_password" --no-auth-warning \
  FCALL dashxd_ratelimit_lifecycle_timer_cancel_v1 0 2>&1 || true)
[[ "$logma_result" == *"wrong number of arguments"* || "$logma_result" == *"wrong number of argument"* ]] || {
  echo "Logma identity cannot execute the installed lifecycle Function: $logma_result" >&2
  exit 1
}
echo "PASS: Ratelimiter Functions reconciled; bootstrap revoked; scoped Logma Function access verified"
