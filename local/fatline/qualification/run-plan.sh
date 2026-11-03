#!/usr/bin/env bash
set -Eeuo pipefail

plan= gate= workspaces= toolbox= nix_local= scope= agni_checkout= artifact_manifest= check_only=0
while (($#)); do
  case "$1" in
    --plan|--gate|--workspaces|--toolbox|--nix-alpine-local|--scope|--agni-checkout|--artifact-manifest)
      (($# >= 2)) || { echo "Missing value for $1" >&2; exit 2; }
      key=${1#--}; value=$2; shift 2
      case "$key" in
        plan) plan=$value;; gate) gate=$value;; workspaces) workspaces=$value;;
        toolbox) toolbox=$value;; nix-alpine-local) nix_local=$value;; scope) scope=$value;; agni-checkout) agni_checkout=$value;; artifact-manifest) artifact_manifest=$value;;
      esac ;;
    --check-only) check_only=1; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 2;;
  esac
done
[[ -f "$plan" && -n "$gate" && -d "$workspaces" && -n "$toolbox" && -d "$nix_local" && -n "$scope" && -n "$agni_checkout" ]] || {
  echo "Usage: $0 --plan FILE --gate ID --workspaces DIR --toolbox NAME --nix-alpine-local DIR --scope NAME --agni-checkout NAME" >&2
  exit 2
}
command -v python3 >/dev/null || { echo "python3 is required for qualification helpers" >&2; exit 2; }
plan=$(realpath "$plan")
plan_dir=$(dirname "$plan")
agni_root=$(realpath "$plan_dir/../../..")
plan_read() {
  python3 - "$plan" "$@" <<'PY'
import json, sys
plan = json.load(open(sys.argv[1], encoding="utf-8"))
mode, *args = sys.argv[2:]
if mode in ("get", "list"):
    value = plan
    for key in args[0].split("."):
        value = value[key]
    if mode == "list":
        if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
            raise SystemExit("expected a list of strings")
        print("\n".join(value))
    elif isinstance(value, (str, int)):
        print(value)
    else:
        raise SystemExit("expected a scalar string or integer")
elif mode == "modes":
    gate = args[0]
    modes = plan["gates"][gate]["runtimeModes"]
    for key, value in modes.items():
        if not key.startswith("COMPOSITION_") or value not in ("0", "1"):
            raise SystemExit("invalid runtime mode")
        print(f"{key}={value}")
else:
    raise SystemExit("unknown plan query")
PY
}
[[ "$(plan_read get schemaVersion)" == 1 ]] || { echo "Unsupported plan schema" >&2; exit 2; }
name=$(plan_read get name)
retain=${NIX_ALPINE_RETAIN:-0}
[[ "$retain" == 0 || "$retain" == 1 ]] || { echo "NIX_ALPINE_RETAIN must be 0 or 1" >&2; exit 2; }
[[ "$name" =~ ^[a-z][a-z0-9-]*$ ]] || { echo "Invalid plan name" >&2; exit 2; }
declared_entrypoint=$(plan_read get entrypoint)
actual_entrypoint=$(realpath --relative-to="$agni_root" "${BASH_SOURCE[0]}")
[[ "$declared_entrypoint" == "$actual_entrypoint" ]] || { echo "Plan entrypoint does not match this runner" >&2; exit 2; }
plan_hash=$(sha256sum "$plan" | awk '{print $1}')
repo_rev=$(git -C "$agni_root" rev-parse HEAD)
source "$plan_dir/sources"
for component in logma skymill; do
  branch_var="COMPOSITION_${component^^}_BRANCH"
  rev_var="COMPOSITION_${component^^}_REV"
  repo=$(plan_read get "components.$component.repository")
  branch=$(plan_read get "components.$component.branch")
  revision=$(plan_read get "components.$component.revision")
  checkout=$(plan_read get "components.$component.checkout")
  flake=$(plan_read get "components.$component.flake")
  image=$(plan_read get "components.$component.image")
  [[ "$checkout" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || { echo "Invalid $component checkout name in plan" >&2; exit 2; }
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
agni_branch=$(plan_read get components.agni.branch)
[[ "$agni_branch" == "$COMPOSITION_AGNI_BRANCH" ]] || { echo "Plan Agni branch does not match source pin" >&2; exit 2; }
redis_image=$(plan_read get artifacts.redis.image)
nginx_image=$(plan_read get artifacts.nginx.image)
checkout=$agni_checkout
export COMPOSITION_AGNI_CHECKOUT="$checkout" COMPOSITION_AGNI_SOURCE="$agni_root"
export COMPOSITION_AGNI_REV="$repo_rev" COMPOSITION_AGNI_BRANCH="$agni_branch"
export COMPOSITION_LOGMA_REV="$LOGMA_REV" COMPOSITION_SKYMILL_REV="$SKYMILL_REV"
export COMPOSITION_LOGMA_IMAGE="$LOGMA_IMAGE" COMPOSITION_SKYMILL_IMAGE="$SKYMILL_IMAGE"
export COMPOSITION_REDIS_IMAGE="$redis_image" COMPOSITION_NGINX_IMAGE="$nginx_image"

if [[ "$gate" == all ]]; then
  mapfile -t selected < <(plan_read list all)
else
  plan_read get "gates.$gate.description" >/dev/null || { echo "Unknown gate: $gate" >&2; exit 2; }
  selected=("$gate")
fi
((${#selected[@]})) || { echo "Unknown gate: $gate" >&2; exit 2; }

make_nix() { command make -C "$nix_local" --no-print-directory "$@" SCOPE="$scope" WORKSPACES="$workspaces" CONTAINER="$toolbox"; }
prepare_artifact() {
  local artifact=$1 flake target image
  flake=$(plan_read get "artifacts.$artifact.flake")
  target=$(plan_read get "artifacts.$artifact.target")
  image=$(plan_read get "artifacts.$artifact.image")
  if [[ -n "$artifact_manifest" ]]; then
    local row expected_id filename archive_digest actual_id
    row=$(awk -F '\t' -v image="$image" '$1 == image { print; count++ } END { if (count != 1) exit 1 }' "$artifact_manifest") || {
      echo "FAIL: artifact manifest must contain exactly one row for $image" >&2; exit 1;
    }
    IFS=$'\t' read -r _ expected_id filename archive_digest <<< "$row"
    [[ "$expected_id" =~ ^sha256:[a-f0-9]{64}$ && "$filename" =~ ^[a-f0-9]{64}\.tar\.gz$ && "$archive_digest" =~ ^[a-f0-9]{64}$ ]] || {
      echo "FAIL: malformed artifact manifest row for $image" >&2; exit 1;
    }
    actual_id=$(podman image inspect "$image" --format '{{.Id}}')
    actual_id="sha256:${actual_id#sha256:}"
    [[ "$actual_id" == "$expected_id" ]] || {
      echo "FAIL: loaded artifact identity mismatch for $image (expected $expected_id, got $actual_id)" >&2; exit 1;
    }
    echo "PASS: cached $artifact image identity $actual_id matches the verified archive manifest"
    return
  fi
  if [[ "$flake" == agni/* ]]; then flake="$checkout/${flake#agni/}"; fi
  make_nix build FLAKE="$flake" TARGET="$target"
  make_nix image-load FLAKE="$flake" TARGET="$target"
  podman image inspect "$image" --format "PASS: loaded $artifact image {{.Id}}"
}
prepare_component() {
  local component=$1 key repo branch rev checkout flake image actual_rev
  key="${component^^}_REPO"; repo=${!key}
  key="${component^^}_BRANCH"; branch=${!key}
  key="${component^^}_REV"; rev=${!key}
  key="${component^^}_CHECKOUT"; checkout=${!key}
  key="${component^^}_FLAKE"; flake=${!key}
  key="${component^^}_IMAGE"; image=${!key}
  actual_rev=$(git -C "$workspaces/$checkout" rev-parse HEAD 2>/dev/null) || {
    echo "FAIL: $component source checkout is missing; sync it through the host plan source manifest" >&2; exit 1;
  }
  [[ "$actual_rev" == "$rev" ]] || {
    echo "FAIL: $component source revision mismatch (expected $rev, got $actual_rev)" >&2; exit 1;
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
  done < <(plan_read modes "$gate_name")
  if [[ "$gate_name" == production-acl ]]; then
    modes+=("COMPOSITION_AGNI_RECONCILE_MODE=1" "COMPOSITION_ACL_ISOLATION_MODE=1" "COMPOSITION_SKYMILL_ACL_MODE=1")
    podman exec "$toolbox" nix run --no-write-lock-file \
      "/workspaces/$checkout/local/fatline#check-acl-pins" -- \
      "/workspaces/$checkout/local/fatline/acl-policy.json" "$LOGMA_REV" "$SKYMILL_REV"
  fi
  ((${#modes[@]} == 0)) || export "${modes[@]}"
  local host_workspaces=${NIX_ALPINE_HOST_WORKSPACES:-}
  [[ -n "$host_workspaces" ]] || { echo "NIX_ALPINE_HOST_WORKSPACES is required for host Podman bind mounts" >&2; return 2; }
  [[ -d "$host_workspaces" ]] || { echo "Host-visible workspace is not mounted: $host_workspaces" >&2; return 2; }
  host_workspaces=$(realpath "$host_workspaces")
  export COMPOSITION_RUNTIME_ROOT="$host_workspaces/.nix-alpine-runtime"
  if [[ "$retain" == 1 && "$gate_name" == "${selected[-1]}" ]]; then
    export COMPOSITION_RETAIN=1
  else
    unset COMPOSITION_RETAIN || true
  fi
  cd "$plan_dir"
  bash ./fatline-composition-preflight.sh "$toolbox" "$redis_image" "$nginx_image" "$LOGMA_IMAGE"
  bash ./fatline-composition-runtime.sh "$toolbox" "$redis_image" "$nginx_image" "$LOGMA_IMAGE"
  for mode in "${modes[@]}"; do unset "${mode%%=*}"; done
  unset COMPOSITION_RETAIN COMPOSITION_RUNTIME_ROOT || true
}

printf 'Plan: %s (%s)\nPlan SHA-256: %s\nAgni revision: %s\nGate selection: %s\n' "$name" "$plan" "$plan_hash" "$repo_rev" "$gate"
if (( check_only )); then
  printf 'Selected gates:\n'
  printf '  %s\n' "${selected[@]}"
  exit 0
fi
python3 "$agni_root/local/fatline/scripts/test-render-users-acl.py"
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
