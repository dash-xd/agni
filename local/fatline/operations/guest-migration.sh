#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/output.sh"

# Host-side application workflow. nix.xd remains a generic Nix/SSH transport.
operation=${1:?Choose assess, verify, review, migrate-stage, migrate-verify, migrate-activation-plan, migrate-activation-check or migrate-recovery-qualify or migrate-activate-sandbox}
deployment=${DEPLOYMENT:-vm1}
nix_xd=${NIX_XD_DIR:-}
provider=${PROVIDER:-podman}
owner_scope=${OWNER_SCOPE:-nix-xd-arm}
machine=${MACHINE:-coreos-arm64}

fail() { printf 'AGNI_DEPLOYMENT=blocked reason=%s\n' "$*" >&2; exit 1; }
case "$deployment" in
  vm1)
    profile_scope=fatline-arm-vm1
    guest_instance=${GUEST_VM_INSTANCE:-starwisp}
    guest_user=${GUEST_SSH_USER:-wisp}
    guest_port=${GUEST_SSH_PORT:-2222}
    ;;
  *) fail "unsupported-deployment:$deployment" ;;
esac
[[ "$provider" == podman || "$provider" == container ]] || fail unsupported-provider
[[ -n "$nix_xd" && -f "$nix_xd/Makefile" ]] || fail missing-nix-xd-directory
nix_xd="$(cd "$nix_xd" && pwd -P)"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
checkout=${AGNI_CHECKOUT:-$(basename "$here")}
[[ "$checkout" =~ ^[A-Za-z0-9_.-]+$ ]] || fail invalid-checkout
[[ "$here" == "$(cd "$nix_xd/.." && pwd -P)/$checkout" ]] || fail workspace-checkout-mismatch
[[ -z "$(git -C "$here" status --porcelain --untracked-files=no)" ]] || fail uncommitted-agni-source
revision="$(git -C "$here" rev-parse HEAD)"
[[ "$revision" =~ ^[a-f0-9]{40}$ ]] || fail invalid-revision
guest_key=${GUEST_SSH_KEY:-"$HOME/.ssh/starwisp-test"}
guest_state=${GUEST_STATE_ROOT:-"$HOME/.local/state/nix-xd/coreos"}
guest_host=${GUEST_SSH_HOST:-127.0.0.1}
flake="$checkout/local/fatline"
log_dir="$(mktemp -d)"
trap 'rm -rf -- "$log_dir"' EXIT

xd_make() {
  make --no-print-directory -C "$nix_xd" "$@" MACHINE="$machine" \
    PROVIDER="$provider" SCOPE="$owner_scope"
}
guest() {
  local mode="$1" bundle="${2:-}" assessment="${3:-}" args
  args="$(python3 - "$mode" "$profile_scope" "$bundle" "$assessment" <<'PY'
import json,sys
items=sys.argv[1:3]
if sys.argv[3]: items.append(sys.argv[3])
if sys.argv[4]: items.append(sys.argv[4])
print(json.dumps(items,separators=(',',':')))
PY
)"
  xd_make guest-app FLAKE="$flake" TARGET='#vm1-probot-guest-stage' \
    GUEST_APP_REV="$revision" ARGS_JSON="$args" \
    GUEST_VM_INSTANCE="$guest_instance" GUEST_STATE_ROOT="$guest_state" \
    GUEST_SSH_USER="$guest_user" GUEST_SSH_PORT="$guest_port" \
    GUEST_SSH_HOST="$guest_host" GUEST_SSH_KEY="$guest_key"
}
run_step() {
  local output="$1";shift
  "$@" | tee "$output"
}

[[ "$operation" == assess || "$operation" == verify || "$operation" == review || "$operation" == migrate-stage || "$operation" == migrate-verify || "$operation" == migrate-activation-plan || "$operation" == migrate-activation-check || "$operation" == migrate-recovery-qualify || "$operation" == migrate-activate-sandbox || "$operation" == recover-sandbox-http || "$operation" == qualify-runtime || "$operation" == diagnose-runtime-network || "$operation" == qualify-integration || "$operation" == qualify-worker-candidate || "$operation" == qualify-worker-live || "$operation" == qualify-worker-bootstrap || "$operation" == qualify-worker-delivery || "$operation" == qualify-worker-recovery || "$operation" == qualify-worker-memory || "$operation" == qualify-worker-fence || "$operation" == qualify-worker-effect || "$operation" == qualify-worker-reconcile || "$operation" == qualify-reconcile-service-contract || "$operation" == seed-reconcile-source || "$operation" == refresh-reconcile-auth || "$operation" == qualify-reconcile-live || "$operation" == seed-processor-source || "$operation" == qualify-processor-contract || "$operation" == qualify-processor-live ]] || fail unsupported-operation
echo "AGNI_DEPLOYMENT_SELECTED=passed deployment=$deployment scope=$profile_scope operation=$operation source=$revision"
xd_make stage CHECKOUT="$checkout" | tee "$log_dir/stage.log"
grep -Fq "Staged $checkout at $revision" "$log_dir/stage.log" || fail staged-source-not-pinned

if [[ "$operation" == refresh-reconcile-auth ]]; then
  xd_make stage CHECKOUT=smoke20261112
  run_step "$log_dir/refresh-reconcile-auth.log" \
    make --no-print-directory -C "$nix_xd" project-host-run \
      MACHINE="$machine" PROVIDER="$provider" SCOPE="$owner_scope" \
      PROJECT=smoke20261112 APPLICATION=ghxd ACTION=auth-refresh
  grep -Fxq 'GHXD_AUTH_REFRESH=passed persistence=sops-age' "$log_dir/refresh-reconcile-auth.log" || fail smoke-ghxd-refresh-not-qualified
  echo 'AGNI_DEPLOYMENT=passed deployment=vm1 operation=refresh-reconcile-auth credential=smoke-ghxd-encrypted production=unchanged'
  exit 0
fi

if [[ "$operation" == seed-reconcile-source ]]; then
  # Smoke owns encrypted OAuth and exact-SHA sources in its dedicated GHXD volumes.
  # The control plane injects only a non-secret source manifest.
  xd_make stage CHECKOUT=smoke20261112
  run_step "$log_dir/reconcile-source-seed.log" \
    env SMOKE_GHXD_SOURCE_MANIFEST="$here/local/fatline/qualification/probot-reconcile-ghxd-sources.json" \
    make --no-print-directory -C "$nix_xd" project-host-run \
      MACHINE="$machine" PROVIDER="$provider" SCOPE="$owner_scope" \
      PROJECT=smoke20261112 APPLICATION=ghxd ACTION=source-sync
  grep -Fxq 'GHXD_WORKSPACE_SYNC=passed' "$log_dir/reconcile-source-seed.log" || fail smoke-source-sync-not-qualified
  grep -Fq 'checkout=probot-runtime20261114 sha=1a0ce1f3684c120a8a800e7e63c45f0780bdda09' \
    "$log_dir/reconcile-source-seed.log" || fail smoke-source-identity-not-qualified
  echo 'AGNI_DEPLOYMENT=passed deployment=vm1 operation=seed-reconcile-source execution=smoke-ghxd promotion=blocked'
  exit 0
fi

if [[ "$operation" == qualify-reconcile-service-contract ]]; then
  run_step "$log_dir/reconcile-service-contract.log" xd_make qualify QUALIFY_APP=1 \
    FLAKE="$flake" TARGET='#reconcile-service-contract'
  grep -Fq 'AGNI_RECONCILE_SERVICE_CONTRACT=passed source=1a0ce1f3684c120a8a800e7e63c45f0780bdda09 scope=isolated production_route=absent' \
    "$log_dir/reconcile-service-contract.log" || fail reconciliation-service-contract-not-qualified
  echo 'AGNI_DEPLOYMENT=passed deployment=vm1 operation=qualify-reconcile-service-contract source=pinned production=unchanged'
  exit 0
fi

if [[ "$operation" == qualify-reconcile-live ]]; then
  run_step "$log_dir/reconcile-artifact.log" xd_make run FLAKE="$flake" TARGET='#reconcile-source-artifact'
  source_artifact="$(agni_capture_value AGNI_RECONCILE_SOURCE_ARTIFACT "$log_dir/reconcile-artifact.log")"
  [[ "$source_artifact" =~ ^/nix/store/[0-9a-z]{32}-probot-runtime20261114$ ]] || fail source-artifact-not-pinned
  grep -Fxq 'AGNI_RECONCILE_SOURCE_ARTIFACT_QUALIFIED=passed revision=1a0ce1f3684c120a8a800e7e63c45f0780bdda09 rooted=true' \
    "$log_dir/reconcile-artifact.log" || fail source-artifact-not-qualified
  run_step "$log_dir/reconcile-live.log" guest qualify-worker-live reconcile-service "$source_artifact"
  grep -Fxq 'AGNI_WORKER_LIVE_GATE=passed gate=reconcile-service' "$log_dir/reconcile-live.log" || fail reconcile-service-live-not-qualified
  grep -Fxq 'AGNI_WORKER_LIVE_QUALIFICATION=passed gate=reconcile-service backing=real service_invocations=unchanged worker=isolated promotion=blocked' \
    "$log_dir/reconcile-live.log" || fail reconcile-service-baseline-not-qualified
  echo 'AGNI_DEPLOYMENT=passed deployment=vm1 operation=qualify-reconcile-live source=pinned backing=real promotion=blocked'
  exit 0
fi

if [[ "$operation" == seed-processor-source ]]; then
  xd_make stage CHECKOUT=smoke20261112
  run_step "$log_dir/processor-source-seed.log" \
    env SMOKE_GHXD_SOURCE_MANIFEST="$here/local/fatline/qualification/probot-processor-ghxd-sources.json" \
    make --no-print-directory -C "$nix_xd" project-host-run \
      MACHINE="$machine" PROVIDER="$provider" SCOPE="$owner_scope" \
      PROJECT=smoke20261112 APPLICATION=ghxd ACTION=source-sync
  grep -Fxq 'GHXD_WORKSPACE_SYNC=passed' "$log_dir/processor-source-seed.log" || fail processor-source-sync-not-qualified
  grep -Fq 'checkout=probot-runtime20261114 sha=2fd46a6a8730ea153346cbc113d7677ef5ad18cf' \
    "$log_dir/processor-source-seed.log" || fail processor-source-identity-not-qualified
  echo 'AGNI_DEPLOYMENT=passed deployment=vm1 operation=seed-processor-source source=smoke-ghxd production=unchanged'
  exit 0
fi

if [[ "$operation" == qualify-processor-contract ]]; then
  run_step "$log_dir/processor-contract.log" xd_make run FLAKE="$flake" TARGET='#processor-subscriber-contract'
  grep -Fxq 'AGNI_PROBOT_PROCESSOR_CONTRACT=passed source=2fd46a6a8730ea153346cbc113d7677ef5ad18cf hints=optional fallback=bounded stream=authoritative' \
    "$log_dir/processor-contract.log" || fail processor-contract-not-qualified
  echo 'AGNI_DEPLOYMENT=passed deployment=vm1 operation=qualify-processor-contract source=pinned production=unchanged'
  exit 0
fi

if [[ "$operation" == qualify-processor-live ]]; then
  run_step "$log_dir/processor-artifact.log" xd_make run FLAKE="$flake" TARGET='#processor-source-artifact'
  source_artifact="$(agni_capture_value AGNI_PROBOT_PROCESSOR_ARTIFACT "$log_dir/processor-artifact.log")"
  [[ "$source_artifact" =~ ^/nix/store/[a-z0-9]{32}-probot-processor20261114$ ]] || fail processor-source-artifact-not-pinned
  grep -Fxq 'AGNI_PROBOT_PROCESSOR_ARTIFACT_QUALIFIED=passed revision=2fd46a6a8730ea153346cbc113d7677ef5ad18cf rooted=true' \
    "$log_dir/processor-artifact.log" || fail processor-artifact-not-qualified
  run_step "$log_dir/processor-live.log" guest qualify-worker-live processor-subscriber "$source_artifact"
  grep -Fxq 'AGNI_PROBOT_PROCESSOR_LIVE=passed redis=real skymill=real logma=redis-pubsub processors=2 group=shared' \
    "$log_dir/processor-live.log" || fail processor-live-not-qualified
  grep -Fxq 'AGNI_WORKER_LIVE_QUALIFICATION=passed gate=processor-subscriber backing=real service_invocations=unchanged worker=isolated promotion=blocked' \
    "$log_dir/processor-live.log" || fail processor-baseline-not-qualified
  echo 'AGNI_DEPLOYMENT=passed deployment=vm1 operation=qualify-processor-live backing=real promotion=blocked'
  exit 0
fi

if [[ "$operation" == diagnose-runtime-network ]]; then
  guest diagnose-runtime-network
  echo 'AGNI_DEPLOYMENT=observed deployment=vm1 operation=diagnose-runtime-network changes=none'
  exit 0
fi

if [[ "$operation" == qualify-worker-live || "$operation" == qualify-worker-bootstrap || "$operation" == qualify-worker-delivery || "$operation" == qualify-worker-recovery || "$operation" == qualify-worker-memory || "$operation" == qualify-worker-fence || "$operation" == qualify-worker-effect || "$operation" == qualify-worker-reconcile ]]; then
  worker_gate=full
  [[ "$operation" != qualify-worker-bootstrap ]] || worker_gate=bootstrap
  [[ "$operation" != qualify-worker-delivery ]] || worker_gate=delivery
  [[ "$operation" != qualify-worker-recovery ]] || worker_gate=recovery
  [[ "$operation" != qualify-worker-memory ]] || worker_gate=memory
  [[ "$operation" != qualify-worker-fence ]] || worker_gate=fence
  [[ "$operation" != qualify-worker-effect ]] || worker_gate=effect
  [[ "$operation" != qualify-worker-reconcile ]] || worker_gate=reconcile
  run_step "$log_dir/worker-$worker_gate.log" guest qualify-worker-live "$worker_gate"
  grep -Fxq "AGNI_WORKER_LIVE_GATE=passed gate=$worker_gate" "$log_dir/worker-$worker_gate.log" || fail worker-gate-not-qualified
  grep -Fxq "AGNI_WORKER_LIVE_QUALIFICATION=passed gate=$worker_gate backing=real service_invocations=unchanged worker=isolated promotion=blocked" "$log_dir/worker-$worker_gate.log" || fail worker-live-not-qualified
  echo "AGNI_DEPLOYMENT=passed deployment=vm1 operation=$operation gate=$worker_gate worker=isolated-real promotion=blocked"
  exit 0
fi

if [[ "$operation" == qualify-worker-candidate ]]; then
  run_step "$log_dir/worker-candidate.log" guest qualify-worker-candidate
  grep -Fxq 'AGNI_WORKER_CANDIDATE_QUALIFICATION=passed services=unchanged worker=fixture-only promotion=blocked' "$log_dir/worker-candidate.log" || fail worker-candidate-not-qualified
  echo 'AGNI_DEPLOYMENT=passed deployment=vm1 operation=qualify-worker-candidate worker=isolated-fixture promotion=blocked'
  exit 0
fi

if [[ "$operation" == qualify-integration ]]; then
  run_step "$log_dir/integration.log" guest qualify-integration
  grep -Fq 'AGNI_PROBOT_INTEGRATION=passed ' "$log_dir/integration.log" || fail probot-integration-not-passed
  echo 'AGNI_DEPLOYMENT=passed deployment=vm1 operation=qualify-integration worker=disabled webhook=not-qualified'
  exit 0
fi

if [[ "$operation" == qualify-runtime ]]; then
  run_step "$log_dir/runtime.log" guest qualify-runtime
  grep -Fq 'AGNI_RUNTIME_QUALIFICATION=passed ' "$log_dir/runtime.log" || fail runtime-qualification-not-passed
  echo 'AGNI_DEPLOYMENT=passed deployment=vm1 operation=qualify-runtime webhook=not-qualified'
  exit 0
fi

if [[ "$operation" == recover-sandbox-http ]]; then
  run_step "$log_dir/sandbox-http-recover.log" guest recover-sandbox-http
  grep -Fq 'AGNI_SANDBOX_HTTP_RECOVERY=passed ' "$log_dir/sandbox-http-recover.log" || fail sandbox-http-recovery-not-qualified
  echo 'AGNI_DEPLOYMENT=passed deployment=vm1 operation=recover-sandbox-http webhook=not-qualified'
  exit 0
fi

if [[ "$operation" == migrate-activate-sandbox ]]; then
  [[ "${REDIS_DATA_LOSS_ACK:-}" == DISCARD-VM1-REDIS-MEMORY ]] || fail explicit-ephemeral-redis-ack-required
  run_step "$log_dir/recovery-qualify.log" guest recovery-qualify
  grep -Fq 'AGNI_RECOVERY_QUALIFICATION=passed ' "$log_dir/recovery-qualify.log" || fail recovery-qualification-not-passed
  run_step "$log_dir/activate-sandbox.log" guest migrate-activate-sandbox "$REDIS_DATA_LOSS_ACK"
  grep -Fq 'AGNI_SANDBOX_ACTIVATION=passed ' "$log_dir/activate-sandbox.log" || fail sandbox-activation-not-qualified
  echo 'AGNI_DEPLOYMENT=passed deployment=vm1 operation=migrate-activate-sandbox webhook=not-qualified'
  exit 0
fi

if [[ "$operation" == migrate-verify || "$operation" == migrate-activation-plan || "$operation" == migrate-activation-check || "$operation" == migrate-recovery-qualify ]]; then
  guest_action=migrate-verify
  [[ "$operation" != migrate-activation-plan ]] || guest_action=activation-plan
  [[ "$operation" != migrate-activation-check ]] || guest_action=activation-check
  [[ "$operation" != migrate-recovery-qualify ]] || guest_action=recovery-qualify
  run_step "$log_dir/$guest_action.log" guest "$guest_action"
  grep -Fq 'AGNI_PROBOT_QUADLET_GENERATOR=passed roles=5 ' "$log_dir/$guest_action.log" || fail quadlet-generation-not-qualified
  grep -Fq 'AGNI_PROBOT_MIGRATION_VERIFY=passed roles=5 ' "$log_dir/$guest_action.log" || fail migration-verification-not-qualified
  if [[ "$operation" == migrate-activation-check ]]; then
    grep -Fq 'AGNI_ACTIVATION_BASELINE=passed ' "$log_dir/$guest_action.log" || fail activation-baseline-not-qualified
    grep -Fq 'AGNI_ACTIVATION_CHECK=passed ' "$log_dir/$guest_action.log" || fail activation-preflight-not-qualified
  fi
  if [[ "$operation" == migrate-recovery-qualify ]]; then
    grep -Fq 'AGNI_RECOVERY_RESTORE=passed roles=4 ' "$log_dir/$guest_action.log" || fail recovery-restore-not-qualified
    grep -Fq 'AGNI_RECOVERY_QUADLET=passed roles=4 ' "$log_dir/$guest_action.log" || fail recovery-quadlet-not-qualified
    grep -Fq 'AGNI_RECOVERY_QUALIFICATION=passed ' "$log_dir/$guest_action.log" || fail recovery-not-qualified
  fi
  if [[ "$operation" == migrate-activation-plan ]]; then
    grep -Fq 'AGNI_DEPLOYMENT_ACTIVATION_PLAN=passed deployment=vm1 ' "$log_dir/$guest_action.log" || fail activation-plan-not-qualified
  fi
  echo "AGNI_DEPLOYMENT=passed deployment=$deployment operation=$operation activation=blocked"
  exit 0
fi

run_step "$log_dir/bundle.log" xd_make qualify QUALIFY_APP=1 FLAKE="$flake" \
  TARGET='#qualify-integration' ARGS='--scenario probot-webhook --phase guest-bundle'
grep -Fxq 'AGNI_PROBOT_GUEST_BUNDLE=passed roles=3 credentials=excluded activation=blocked' "$log_dir/bundle.log" || fail bundle-not-qualified
bundle="$(agni_capture_value AGNI_PROBOT_GUEST_BUNDLE_PATH "$log_dir/bundle.log")"
[[ "$bundle" =~ ^/nix/store/[a-z0-9]{32}-candidate$ ]] || fail invalid-qualified-bundle

if [[ "$operation" == verify ]]; then
  run_step "$log_dir/verify.log" guest verify "$bundle"
  grep -Fxq 'AGNI_PROBOT_GUEST_VERIFY=passed activation=blocked' "$log_dir/verify.log" || fail guest-verification-not-qualified
  echo "AGNI_DEPLOYMENT=passed deployment=$deployment operation=verify activation=blocked"
  exit 0
fi

run_step "$log_dir/assess.log" guest adopt-plan "$bundle"
grep -Fq 'AGNI_PROBOT_ADOPTION_ASSESSMENT=passed ' "$log_dir/assess.log" || fail adoption-assessment-not-qualified
assessment_path="$(agni_capture_value AGNI_PROBOT_ADOPTION_ASSESSMENT_PATH "$log_dir/assess.log")"
[[ "$assessment_path" =~ /([0-9a-f]{64})\.json$ ]] || fail invalid-assessment-evidence
assessment="${BASH_REMATCH[1]}"
if [[ "$operation" == assess ]]; then
  echo "AGNI_DEPLOYMENT=passed deployment=$deployment operation=assess activation=blocked"
  exit 0
fi
run_step "$log_dir/review.log" guest adopt-review "$bundle" "$assessment"
grep -Fq 'AGNI_PROBOT_ADOPTION_REVIEW=passed ' "$log_dir/review.log" || fail adoption-review-not-qualified
if [[ "$operation" == review ]]; then
  echo "AGNI_DEPLOYMENT=passed deployment=$deployment operation=review activation=blocked"
  exit 0
fi

run_step "$log_dir/migrate.log" guest adopt-stage "$bundle" "$assessment"
grep -Fq 'AGNI_PROBOT_MIGRATION_STAGE=passed roles=5 ' "$log_dir/migrate.log" || fail migration-stage-not-qualified
echo "AGNI_DEPLOYMENT=passed deployment=$deployment operation=migrate-stage activation=blocked"
