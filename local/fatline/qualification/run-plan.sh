#!/usr/bin/env bash
set -Eeuo pipefail

plan= gate= workspaces= toolbox= nix_local= scope= check_only=0
while (($#)); do
  case "$1" in
    --plan|--gate|--workspaces|--toolbox|--nix-alpine-local|--scope)
      (($# >= 2)) || { echo "Missing value for $1" >&2; exit 2; }
      key=${1#--}; value=$2; shift 2
      case "$key" in
        plan) plan=$value;; gate) gate=$value;; workspaces) workspaces=$value;;
        toolbox) toolbox=$value;; nix-alpine-local) nix_local=$value;; scope) scope=$value;;
      esac ;;
    --check-only) check_only=1; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 2;;
  esac
done
[[ -f "$plan" && -n "$gate" && -d "$workspaces" && -n "$toolbox" && -d "$nix_local" && -n "$scope" ]] || {
  echo "Usage: $0 --plan FILE --gate ID --workspaces DIR --toolbox NAME --nix-alpine-local DIR --scope NAME" >&2
  exit 2
}
command -v jq >/dev/null || { echo "jq is required for plan validation" >&2; exit 2; }
plan=$(realpath "$plan")
plan_dir=$(dirname "$plan")
agni_root=$(realpath "$plan_dir/../../..")
[[ "$(jq -er '.schemaVersion' "$plan")" == 1 ]] || { echo "Unsupported plan schema" >&2; exit 2; }
name=$(jq -er '.name | strings | select(test("^[a-z][a-z0-9-]*$"))' "$plan")
declared_entrypoint=$(jq -er '.entrypoint | strings' "$plan")
actual_entrypoint=$(realpath --relative-to="$agni_root" "${BASH_SOURCE[0]}")
[[ "$declared_entrypoint" == "$actual_entrypoint" ]] || { echo "Plan entrypoint does not match this runner" >&2; exit 2; }
plan_hash=$(sha256sum "$plan" | awk '{print $1}')
repo_rev=$(git -C "$agni_root" rev-parse HEAD)
source "$plan_dir/sources"
for component in logma skymill; do
  branch_var="COMPOSITION_${component^^}_BRANCH"
  rev_var="COMPOSITION_${component^^}_REV"
  checkout_var="COMPOSITION_${component^^}_CHECKOUT"
  repo=$(jq -er ".components.$component.repository" "$plan")
  branch=$(jq -er ".components.$component.branch" "$plan")
  revision=$(jq -er ".components.$component.revision" "$plan")
  flake=$(jq -er ".components.$component.flake" "$plan")
  image=$(jq -er ".components.$component.image" "$plan")
  checkout=${!checkout_var:-${component}-qualification}
  [[ "$branch" == "${!branch_var}" && "$revision" == "${!rev_var}" ]] || {
    echo "Plan pin mismatch for $component; update the plan and sources together" >&2; exit 2;
  }
  printf -v "${component^^}_REPO" '%s' "$repo"
  printf -v "${component^^}_BRANCH" '%s' "$branch"
  printf -v "${component^^}_REV" '%s' "$revision"
  printf -v "${component^^}_FLAKE" '%s' "$flake"
  printf -v "${component^^}_IMAGE" '%s' "$image"
  printf -v "${component^^}_CHECKOUT" '%s' "$checkout"
done
agni_branch=$(jq -er '.components.agni.branch' "$plan")
[[ "$agni_branch" == "$COMPOSITION_AGNI_BRANCH" ]] || { echo "Plan Agni branch does not match source pin" >&2; exit 2; }
redis_image=$(jq -er '.artifacts.redis.image' "$plan")
nginx_image=$(jq -er '.artifacts.nginx.image' "$plan")
checkout=${COMPOSITION_AGNI_CHECKOUT:-agni-qualification}
export COMPOSITION_AGNI_CHECKOUT="$checkout" COMPOSITION_AGNI_SOURCE="$agni_root"
export COMPOSITION_AGNI_REV="$repo_rev" COMPOSITION_AGNI_BRANCH="$agni_branch"
export COMPOSITION_LOGMA_REV="$LOGMA_REV" COMPOSITION_SKYMILL_REV="$SKYMILL_REV"
export COMPOSITION_LOGMA_IMAGE="$LOGMA_IMAGE" COMPOSITION_SKYMILL_IMAGE="$SKYMILL_IMAGE"
export COMPOSITION_REDIS_IMAGE="$redis_image" COMPOSITION_NGINX_IMAGE="$nginx_image"

mapfile -t selected < <(if [[ "$gate" == all ]]; then jq -er '.all[]' "$plan"; else jq -er --arg gate "$gate" '.gates[$gate] | select(type == "object") | $gate' "$plan"; fi)
((${#selected[@]})) || { echo "Unknown gate: $gate" >&2; exit 2; }

make_nix() { command make -C "$nix_local" --no-print-directory "$@" SCOPE="$scope" WORKSPACES="$workspaces" CONTAINER="$toolbox"; }
prepare_artifact() {
  local artifact=$1 flake target image
  flake=$(jq -er --arg artifact "$artifact" '.artifacts[$artifact].flake' "$plan")
  target=$(jq -er --arg artifact "$artifact" '.artifacts[$artifact].target' "$plan")
  image=$(jq -er --arg artifact "$artifact" '.artifacts[$artifact].image' "$plan")
  make_nix build FLAKE="$flake" TARGET="$target"
  make_nix image-load FLAKE="$flake" TARGET="$target"
  podman image inspect "$image" --format "PASS: loaded $artifact image {{.Id}}"
}
prepare_component() {
  local component=$1 key repo branch rev checkout flake image
  key="${component^^}_REPO"; repo=${!key}
  key="${component^^}_BRANCH"; branch=${!key}
  key="${component^^}_REV"; rev=${!key}
  key="${component^^}_CHECKOUT"; checkout=${!key}
  key="${component^^}_FLAKE"; flake=${!key}
  key="${component^^}_IMAGE"; image=${!key}
  make_nix sync REPO="$repo" BRANCH="$branch" SYNC_NAME="$checkout"
  git -C "$workspaces/$checkout" rev-parse HEAD | grep -Fx -- "$rev" >/dev/null || {
    echo "FAIL: $component source revision mismatch (expected $rev)" >&2; exit 1;
  }
  make_nix build FLAKE="$checkout" TARGET="$flake"
  make_nix image-load FLAKE="$checkout" TARGET="$flake"
  podman image inspect "$image" --format "PASS: loaded $component provider image {{.Id}}"
}
run_runtime() {
  local gate_name=$1
  local -a modes=()
  while IFS='=' read -r key value; do
    [[ -n "$key" ]] && modes+=("$key=$value")
  done < <(jq -r --arg gate "$gate_name" '.gates[$gate].runtimeModes | to_entries[] | "\(.key)=\(.value)"' "$plan")
  if [[ "$gate_name" == production-acl ]]; then
    modes+=("COMPOSITION_AGNI_RECONCILE_MODE=1" "COMPOSITION_ACL_ISOLATION_MODE=1" "COMPOSITION_SKYMILL_ACL_MODE=1")
  fi
  ((${#modes[@]} == 0)) || export "${modes[@]}"
  cd "$plan_dir"
  bash ./fatline-composition-preflight.sh "$toolbox" "$redis_image" "$nginx_image" "$LOGMA_IMAGE"
  bash ./fatline-composition-runtime.sh "$toolbox" "$redis_image" "$nginx_image" "$LOGMA_IMAGE"
  for mode in "${modes[@]}"; do unset "${mode%%=*}"; done
}

printf 'Plan: %s (%s)\nPlan SHA-256: %s\nAgni revision: %s\nGate selection: %s\n' "$name" "$plan" "$plan_hash" "$repo_rev" "$gate"
if (( check_only )); then
  printf 'Selected gates:\n'
  printf '  %s\n' "${selected[@]}"
  exit 0
fi
prepare_artifact redis
prepare_artifact nginx
logma_prepared=0
skymill_prepared=0
for selected_gate in "${selected[@]}"; do
  echo "CHECK: $name qualification gate $selected_gate"
  if (( ! logma_prepared )); then prepare_component logma; logma_prepared=1; fi
  if [[ "$selected_gate" == skymill-provider || "$selected_gate" == production-acl ]] && (( ! skymill_prepared )); then
    prepare_component skymill
    skymill_prepared=1
  fi
  run_runtime "$selected_gate"
  echo "PASS: $name qualification gate $selected_gate"
done
