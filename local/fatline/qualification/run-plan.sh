#!/usr/bin/env bash
set -Eeuo pipefail

plan= gate= workspaces= toolbox= nix_local= scope= plan_checkout= artifact_manifest= check_only=0
while (($#)); do
  case "$1" in
    --plan|--gate|--workspaces|--toolbox|--nix-alpine-local|--scope|--plan-checkout|--artifact-manifest)
      (($# >= 2)) || { echo "Missing value for $1" >&2; exit 2; }
      key=${1#--}; value=$2; shift 2
      case "$key" in
        plan) plan=$value;; gate) gate=$value;; workspaces) workspaces=$value;;
        toolbox) toolbox=$value;; nix-alpine-local) nix_local=$value;; scope) scope=$value;; plan-checkout) plan_checkout=$value;; artifact-manifest) artifact_manifest=$value;;
      esac ;;
    --check-only) check_only=1; shift ;;
    *) echo "Unknown argument: $1" >&2; exit 2;;
  esac
done
[[ -f "$plan" && -n "$gate" && -d "$workspaces" && -n "$toolbox" && -d "$nix_local" && -n "$scope" && -n "$plan_checkout" ]] || {
  echo "Usage: $0 --plan FILE --gate ID --workspaces DIR --toolbox NAME --nix-alpine-local DIR --scope NAME --plan-checkout PATH" >&2
  exit 2
}
command -v python3 >/dev/null || { echo "python3 is required for qualification helpers" >&2; exit 2; }
plan=$(realpath "$plan")
plan_dir=$(dirname "$plan")
agni_root=$(realpath "$plan_dir/../../..")
plan_read() {
  python3 - "$plan" "$@" <<'PY'
import json, re, sys
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
    module_id = f"runtime-{gate}"
    modes = plan["modules"][module_id]["inputs"].get("runtimeModes", {})
    for key, value in modes.items():
        if not key.startswith("COMPOSITION_") or value not in ("0", "1"):
            raise SystemExit("invalid runtime mode")
        print(f"{key}={value}")
elif mode == "module-order":
    gate = args[0]
    modules = plan.get("modules")
    if not isinstance(modules, dict) or not modules:
        raise SystemExit("plan must declare qualification modules")
    expected_phases = {
        "nix.build-image": ["prepare", "verify"],
        "nix.build-provider": ["prepare", "verify"],
        "acl.verify-policy": ["prepare", "verify"],
        "podman-systemd.composition-gate": ["prepare", "execute", "verify", "cleanup"],
    }
    allowed_kinds = set(expected_phases)
    allowed_phases = {"prepare", "execute", "verify", "cleanup"}
    output_owners = {}
    for module_id, module in modules.items():
        if not isinstance(module, dict) or module.get("kind") not in allowed_kinds:
            raise SystemExit(f"invalid module kind: {module_id}")
        if not isinstance(module.get("phases"), list) or not set(module["phases"]) <= allowed_phases or module["phases"] != expected_phases[module["kind"]]:
            raise SystemExit(f"invalid module phases: {module_id}")
        if not isinstance(module.get("inputs"), dict) or not isinstance(module.get("outputs"), list) or not all(isinstance(x, str) and x for x in module["outputs"]):
            raise SystemExit(f"invalid module inputs or outputs: {module_id}")
        if not re.fullmatch(r"[a-z][a-z0-9-]*", module_id):
            raise SystemExit(f"invalid module ID: {module_id}")
        if not isinstance(module.get("dependsOn"), list) or not all(isinstance(x, str) for x in module["dependsOn"]):
            raise SystemExit(f"invalid module dependencies: {module_id}")
        if len(module["dependsOn"]) != len(set(module["dependsOn"])):
            raise SystemExit(f"duplicate module dependency: {module_id}")
        inputs = module["inputs"]
        if module["kind"] == "nix.build-image" and inputs.get("artifact") not in plan.get("artifacts", {}):
            raise SystemExit(f"unknown image artifact input: {module_id}")
        if module["kind"] == "nix.build-provider" and inputs.get("component") not in plan.get("components", {}):
            raise SystemExit(f"unknown provider component input: {module_id}")
        if module["kind"] == "acl.verify-policy" and (not isinstance(inputs.get("policy"), str) or inputs["policy"].startswith("/") or ".." in inputs["policy"]):
            raise SystemExit(f"invalid ACL policy input: {module_id}")
        if module["kind"] == "podman-systemd.composition-gate":
            gate_name = inputs.get("gate")
            if module_id != f"runtime-{gate_name}" or gate_name not in plan.get("gates", {}):
                raise SystemExit(f"invalid runtime gate input: {module_id}")
            modes = inputs.get("runtimeModes", {})
            if not isinstance(modes, dict) or any(not isinstance(k, str) or not k.startswith("COMPOSITION_") or v not in ("0", "1") for k, v in modes.items()):
                raise SystemExit(f"invalid runtime mode declaration: {module_id}")
        for output in module["outputs"]:
            if output in output_owners:
                raise SystemExit(f"duplicate module output {output}: {output_owners[output]} and {module_id}")
            output_owners[output] = module_id
        cleanup = module.get("cleanup")
        expected_cleanup = "retainable" if module["kind"] == "podman-systemd.composition-gate" else "preserve"
        if not isinstance(cleanup, dict) or cleanup.get("policy") != expected_cleanup:
            raise SystemExit(f"invalid module cleanup policy: {module_id}")
        if cleanup["policy"] == "retainable" and (cleanup.get("scope") != "module-run" or cleanup.get("override") != "RETAIN"):
            raise SystemExit(f"retainable cleanup must declare scope and RETAIN override: {module_id}")
    for module_id, module in modules.items():
        missing = [dep for dep in module["dependsOn"] if dep not in modules]
        if missing:
            raise SystemExit(f"unknown dependency for {module_id}: {missing[0]}")
    gate_modules = plan["gates"][gate].get("modules")
    if not isinstance(gate_modules, list) or not gate_modules:
        raise SystemExit(f"gate has no entry modules: {gate}")
    ordered = []
    visiting = set()
    visited = set()
    def visit(module_id):
        if module_id not in modules:
            raise SystemExit(f"unknown gate module: {module_id}")
        if module_id in visiting:
            raise SystemExit(f"module dependency cycle at: {module_id}")
        if module_id in visited:
            return
        visiting.add(module_id)
        for dep in modules[module_id]["dependsOn"]:
            visit(dep)
        visiting.remove(module_id)
        visited.add(module_id)
        ordered.append(module_id)
    for module_id in gate_modules:
        visit(module_id)
    print("\n".join(ordered))
else:
    raise SystemExit("unknown plan query")
PY
}
[[ "$(plan_read get schemaVersion)" == 2 && "$(plan_read get protocolVersion)" == 1 ]] || { echo "Unsupported qualification plan protocol" >&2; exit 2; }
name=$(plan_read get name)
retain=${NIX_ALPINE_RETAIN:-0}
[[ "$retain" == 0 || "$retain" == 1 ]] || { echo "NIX_ALPINE_RETAIN must be 0 or 1" >&2; exit 2; }
[[ "$name" =~ ^[a-z][a-z0-9-]*$ ]] || { echo "Invalid plan name" >&2; exit 2; }
declared_entrypoint=$(plan_read get entrypoint)
actual_entrypoint=$(realpath --relative-to="$agni_root" "${BASH_SOURCE[0]}")
[[ "$declared_entrypoint" == "$actual_entrypoint" ]] || { echo "Plan entrypoint does not match this runner" >&2; exit 2; }
plan_hash=$(sha256sum "$plan" | awk '{print $1}')
repo_rev=$(git -C "$agni_root" rev-parse HEAD)
source_manifest="$plan_dir/sources.tsv"
[[ -r "$source_manifest" ]] || { echo "Missing component source lock: $source_manifest" >&2; exit 2; }
read_source_pin() {
  local component=$1 rows repo revision checkout flake image
  rows=$(awk -F '\t' -v component="$component" '$1 == component { print $2 "\t" $3 "\t" $4; count++ } END { if (count != 1) exit 1 }' "$source_manifest") || {
    echo "Expected exactly one source pin for $component" >&2; exit 2;
  }
  IFS=$'\t' read -r repo revision checkout <<< "$rows"
  [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "Invalid repository pin for $component" >&2; exit 2; }
  [[ "$revision" =~ ^[0-9a-f]{40}$ ]] || { echo "Invalid revision pin for $component" >&2; exit 2; }
  [[ "$checkout" != /* && "$checkout" != *//* ]] || { echo "Invalid checkout path for $component" >&2; exit 2; }
  IFS=/ read -r -a checkout_parts <<< "$checkout"
  for checkout_part in "${checkout_parts[@]}"; do
    [[ "$checkout_part" =~ ^[A-Za-z0-9_.-]+$ && "$checkout_part" != "." && "$checkout_part" != ".." && "$checkout_part" != ".git" ]] || {
      echo "Invalid checkout path for $component" >&2; exit 2;
    }
  done
  checkout_root=$(realpath "$workspaces/$checkout")
  checkout_rel=$(realpath --relative-to="$workspaces" "$checkout_root")
  [[ "$checkout_rel" == "$checkout" ]] || { echo "$component checkout resolves outside workspace" >&2; exit 2; }
  [[ "$(git -C "$checkout_root" rev-parse HEAD)" == "$revision" ]] || {
    echo "$component checkout revision differs from source lock" >&2; exit 2;
  }
  flake=$(plan_read get "components.$component.flake")
  image=$(plan_read get "components.$component.image")
  printf -v "${component^^}_REPO" '%s' "$repo"
  printf -v "${component^^}_REV" '%s' "$revision"
  printf -v "${component^^}_FLAKE" '%s' "$flake"
  printf -v "${component^^}_IMAGE" '%s' "$image"
  printf -v "${component^^}_CHECKOUT" '%s' "$checkout"
}
for component in logma skymill; do read_source_pin "$component"; done
redis_image=$(plan_read get artifacts.redis.image)
nginx_image=$(plan_read get artifacts.nginx.image)
checkout=$plan_checkout
export COMPOSITION_AGNI_CHECKOUT="$checkout" COMPOSITION_AGNI_SOURCE="$agni_root"
export COMPOSITION_AGNI_REV="$repo_rev"
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
declare -A gate_module_orders=()
for selected_gate in "${selected[@]}"; do
  plan_read get "gates.$selected_gate.description" >/dev/null || { echo "Unknown gate: $selected_gate" >&2; exit 2; }
  gate_module_orders["$selected_gate"]=$(plan_read module-order "$selected_gate") || {
    echo "Invalid module graph for gate $selected_gate" >&2; exit 2;
  }
done


make_nix() { command make -C "$nix_local" --no-print-directory "$@" SCOPE="$scope" WORKSPACES="$workspaces" CONTAINER="$toolbox"; }
prepare_artifact() {
  local artifact=$1 flake target image
  flake=$(plan_read get "artifacts.$artifact.flake")
  target=$(plan_read get "artifacts.$artifact.target")
  image=$(plan_read get "artifacts.$artifact.image")
  build_image=$(plan_read get "artifacts.$artifact.buildImage")
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
  podman image inspect "$build_image" >/dev/null
  if [[ "$build_image" != "$image" ]]; then
    podman image tag "$build_image" "$image"
  fi
  podman image inspect "$image" --format "PASS: loaded $artifact image {{.Id}}"
}
prepare_component() {
  local component=$1 key repo rev checkout flake image actual_rev
  key="${component^^}_REPO"; repo=${!key}
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
  for selected_gate in "${selected[@]}"; do
    printf 'Modules for %s:\n%s\n' "$selected_gate" "${gate_module_orders[$selected_gate]}"
  done
  exit 0
fi
declare -A completed_modules=()
run_module() {
  local module_id=$1 kind input
  kind=$(plan_read get "modules.$module_id.kind")
  case "$kind" in
    nix.build-image)
      input=$(plan_read get "modules.$module_id.inputs.artifact")
      prepare_artifact "$input"
      ;;
    nix.build-provider)
      input=$(plan_read get "modules.$module_id.inputs.component")
      prepare_component "$input"
      ;;
    acl.verify-policy)
      input=$(plan_read get "modules.$module_id.inputs.policy")
      python3 "$agni_root/local/fatline/scripts/test-render-users-acl.py"
      podman exec "$toolbox" nix run --no-write-lock-file \
        "/workspaces/$checkout/local/fatline#check-acl-pins" -- \
        "/workspaces/$checkout/local/fatline/$input" "$LOGMA_REV" "$SKYMILL_REV"
      ;;
    podman-systemd.composition-gate)
      input=$(plan_read get "modules.$module_id.inputs.gate")
      run_runtime "$input"
      ;;
    *) echo "Unsupported qualification module kind: $kind" >&2; return 2;;
  esac
}
for selected_gate in "${selected[@]}"; do
  echo "CHECK: $name qualification gate $selected_gate"
  module_order=${gate_module_orders[$selected_gate]}
  while IFS= read -r module_id; do
    [[ -n "$module_id" ]] || continue
    [[ -n "${completed_modules[$module_id]:-}" ]] && continue
    printf 'CHECK: qualification module %s (%s)\n' "$module_id" "$(plan_read get "modules.$module_id.kind")"
    run_module "$module_id"
    outputs=$(plan_read list "modules.$module_id.outputs") || { echo "Could not read module outputs: $module_id" >&2; exit 2; }
    completed_modules["$module_id"]=1
    printf 'PASS: qualification module %s; declared outputs:\n%s\n' "$module_id" "$outputs"
  done <<< "$module_order"
  echo "PASS: $name qualification gate $selected_gate"
done
