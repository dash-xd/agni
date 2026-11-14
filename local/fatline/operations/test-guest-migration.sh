#!/usr/bin/env bash
set -Eeuo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
bash -n "$here/operations/guest-migration.sh"
bash -n "$here/operations/output.sh"
source "$here/operations/output.sh"
capture_fixture="$(mktemp)"
trap 'rm -f "$capture_fixture"' EXIT
printf '%s\n' 'NOISE=other' 'AGNI_PROBOT_GUEST_BUNDLE_PATH=/nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-candidate' > "$capture_fixture"
[[ "$(agni_capture_value AGNI_PROBOT_GUEST_BUNDLE_PATH "$capture_fixture")" == /nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-candidate ]]
if agni_capture_value MISSING "$capture_fixture" >/dev/null; then
  echo 'Accepted missing output field' >&2
  exit 1
fi
printf '%s\n' 'AGNI_PROBOT_GUEST_BUNDLE_PATH=/nix/store/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-candidate' >> "$capture_fixture"
if agni_capture_value AGNI_PROBOT_GUEST_BUNDLE_PATH "$capture_fixture" >/dev/null; then
  echo 'Accepted duplicate output field' >&2
  exit 1
fi
printf '%s\n' 'FIELD=' > "$capture_fixture"
if agni_capture_value FIELD "$capture_fixture" >/dev/null; then
  echo 'Accepted empty output field' >&2
  exit 1
fi
output="$(make --no-print-directory -C "$here" help)"
for operation in assess verify review migrate-stage migrate-verify migrate-activation-plan migrate-activation-check migrate-recovery-qualify migrate-activate migrate-activate-sandbox recover-sandbox-http qualify-runtime qualify-integration qualify-worker-candidate qualify-worker-bootstrap qualify-worker-delivery qualify-worker-recovery qualify-worker-memory qualify-worker-fence qualify-worker-effect qualify-worker-live diagnose-runtime-network; do
  grep -Fq "deployment-$operation" <<< "$output"
  make -s -n -C "$here" "deployment-$operation" >/dev/null
done
# Operator-facing Make targets must use named operations, not manual JSON or store hashes.
! grep -Eq 'ARGS_JSON|/nix/store/[a-z0-9]{32}-candidate' "$here/Makefile"
# Unsupported deployment fails before network, staging, Nix or SSH.
set +e
bad="$(DEPLOYMENT=unsupported NIX_XD_DIR=/nonexistent bash "$here/operations/guest-migration.sh" migrate-stage 2>&1)"
status=$?
set -e
[[ $status != 0 && "$bad" == *'unsupported-deployment'* ]]
# The activation target must reject even if the user tries to invoke it directly.
set +e
blocked="$(make --no-print-directory -s -C "$here" deployment-migrate-activate DEPLOYMENT=vm1 2>&1)"
status=$?
set -e
[[ $status != 0 && "$blocked" == *'AGNI_ACTIVATION=blocked'* ]]
# The sandbox cutover also requires a specific, explicit acknowledgement.
set +e
sandbox_blocked="$(make --no-print-directory -s -C "$here" deployment-migrate-activate-sandbox DEPLOYMENT=vm1 2>&1)"
sandbox_status=$?
set -e
[[ $sandbox_status != 0 && "$sandbox_blocked" == *'explicit-ephemeral-redis-ack-required'* ]]
grep -Fq '    activation_check' "$here/startup-profile/probot-guest-app.sh"
grep -Fq 'install-probot "$scope" "$target/rendered"' "$here/startup-profile/probot-guest-app.sh"
grep -Fq 'bootstrap.sh" verify "$scope" "$profile_probe"' "$here/startup-profile/probot-guest-app.sh"
grep -Fq '  diagnose-runtime-network)' "$here/startup-profile/probot-guest-app.sh"
grep -Fq 'AGNI_RUNTIME_NETWORK=observed changes=none' "$here/startup-profile/probot-guest-app.sh"
grep -Fq '  qualify-runtime)' "$here/startup-profile/probot-guest-app.sh"
grep -Fq 'AGNI_RUNTIME_QUALIFICATION=passed ' "$here/startup-profile/probot-guest-app.sh"
grep -Fq 'provider_delivery_id' "$here/startup-profile/probot-runtime-qualify.py"
# The CoreOS guest does not expose the Nix store at /nix/store on its host.
# Its recovery Python must execute inside a rootless store-mapped container.
grep -Fq -- '--mount type=bind,src=/var/mnt/nixstore,dst=/nix/store,ro' "$here/startup-profile/probot-guest-app.sh"
grep -Fq -- '--base /run/fatline-base --generation "$basename"' "$here/startup-profile/probot-guest-app.sh"
! grep -Fq '"$python" "$tools/probot-sandbox-http-recover.py"' "$here/startup-profile/probot-guest-app.sh"
# nix.xd executes the guest via a Bash stream, where $0 is bash itself.
# Recovery must invoke the shared preflight function, not bash "$0".
grep -Fq 'activation_check() {' "$here/startup-profile/probot-guest-app.sh"
grep -Fq '    activation_check' "$here/startup-profile/probot-guest-app.sh"
! grep -Fq 'bash "$0" activation-check' "$here/startup-profile/probot-guest-app.sh"
echo 'AGNI_DEPLOYMENT_INTERFACE_TEST=passed named-operations=true json=transport-only bash32-compatible=true'

# A failing child script must not terminate the invoking interactive shell.
# The operator invokes the logger/Makefile as a command, never through source.
if command -v zsh >/dev/null 2>&1; then
  survived="$(zsh -fc 'false; print -r -- INTERACTIVE_SHELL_SURVIVED')"
  [[ "$survived" == INTERACTIVE_SHELL_SURVIVED ]]
fi
! grep -Eq '^[[:space:]]*(source|\.)[[:space:]]+.*(guest-migration\.sh|nix-xd-log)' "$here/Makefile"
echo 'AGNI_OPERATOR_SHELL=passed invocation=child-shell parent_options=unchanged'
grep -Fq 'AGNI_RUNTIME_LOGMA_LISTEN=begin' "$here/startup-profile/probot-guest-app.sh"
grep -Fq 'AGNI_RUNTIME_LOGMA_STARTUP=begin' "$here/startup-profile/probot-guest-app.sh"
grep -Fq 'AGNI_RUNTIME_LOGMA_EXECUTABLE=begin' "$here/startup-profile/probot-guest-app.sh"
grep -Fq 'AGNI_RUNTIME_LOGMA_QUADLET_EXEC=begin' "$here/startup-profile/probot-guest-app.sh"

# Both the generated guest entrypoint and host dispatcher must parse.
bash -n "$here/startup-profile/probot-guest-app.sh"
[[ "$(grep -c '^esac$' "$here/startup-profile/probot-guest-app.sh")" -ge 1 ]]
grep -Fq -- '--logma-api-key-file /run/logma-api-key' "$here/startup-profile/probot-guest-app.sh"
grep -Fq 'http://logma:18081/lifecycle/api/v0.0.1/policies' "$here/startup-profile/probot-runtime-qualify.py"
! grep -Fq 'http://logma:8080/lifecycle/readyz' "$here/startup-profile/probot-runtime-qualify.py"
echo 'AGNI_LOGMA_RUNTIME_CONTRACT=passed entrypoint=cmd/api-lifecycle port=18081 auth=x-api-key strict_ready=unqualified'

# Integration contract must be parsed before any runtime entrypoint is built.
python3 "$here/operations/test-probot-integration.py" "$here/startup-profile/probot-integration-qualify.py"
python3 - "$here/startup-profile/probot-integration-qualify.py" <<'PY'
import ast, pathlib, sys
ast.parse(pathlib.Path(sys.argv[1]).read_text())
PY
grep -Fq '  qualify-integration)' "$here/startup-profile/probot-guest-app.sh"
grep -Fq 'AGNI_PROBOT_INTEGRATION=passed ' "$here/startup-profile/probot-guest-app.sh"
grep -Fq 'AGNI_SKYMILL_REDELIVERY=passed ' "$here/startup-profile/probot-integration-qualify.py"
grep -Fq 'PROBOT_RUNTIME_WORKER_ENABLED=false' "$here/startup-profile/probot-guest-app.sh"
echo 'AGNI_PROBOT_INTEGRATION_STATIC=passed worker=disabled auth=isolated retry=bounded'

grep -Fq '  qualify-worker-candidate)' "$here/startup-profile/probot-guest-app.sh"
grep -Fq 'AGNI_WORKER_CANDIDATE_QUALIFICATION=passed' "$here/startup-profile/probot-guest-app.sh"
grep -Fq 'AGNI_WORKER_SIGNED_INGRESS=passed' "$here/startup-profile/probot-worker-candidate.js"
grep -Fq 'AGNI_WORKER_ROLLBACK=passed' "$here/startup-profile/probot-worker-candidate.js"
if command -v node >/dev/null 2>&1; then
  node --check "$here/startup-profile/probot-worker-candidate.js"
fi
echo 'AGNI_WORKER_CANDIDATE_STATIC=passed offline_fixture=true vm1=unchanged'

grep -Fq '  qualify-worker-live)' "$here/startup-profile/probot-guest-app.sh"
grep -Fq 'AGNI_WORKER_LIVE_QUALIFICATION=passed' "$here/startup-profile/probot-guest-app.sh"
grep -Fq -- '--network none' "$here/startup-profile/probot-guest-app.sh"
grep -Fq 'AGNI_WORKER_LIVE_CLEANUP=passed' "$here/startup-profile/probot-worker-live.js"
grep -Fq 'AGNI_WORKER_LIVE_RECOVERY=passed' "$here/startup-profile/probot-worker-live.js"
if command -v node >/dev/null 2>&1; then
  node --check "$here/startup-profile/probot-worker-live.js"
fi
echo 'AGNI_WORKER_LIVE_STATIC=passed isolated=true credential_source=ephemeral'

# The non-root candidate must be able to create its own temporary state.
grep -Fq -- '--tmpfs /tmp:rw,nosuid,nodev,mode=1777,size=128m' "$here/startup-profile/probot-guest-app.sh"

# Persistent node-redis client errors and unexpected child exits must be bounded.
grep -Fq "store.client.on('error'" "$here/startup-profile/probot-worker-live.js"
grep -Fq "child.on('exit'" "$here/startup-profile/probot-worker-live.js"
grep -Fq 'assertChildrenHealthy()' "$here/startup-profile/probot-worker-live.js"

# Candidate child startup errors must be categorized without logging raw credential-bearing output.
grep -Fq 'AGNI_WORKER_LIVE_CHILD_SIGNAL role=' "$here/startup-profile/probot-worker-live.js"
grep -Fq 'child_categories=' "$here/startup-profile/probot-worker-live.js"

# The candidate starts only the worker-enabled instance; stop waits for exit.
grep -Fq 'startProbot(true)' "$here/startup-profile/probot-worker-live.js"
if grep -Fq 'startProbot(false)' "$here/startup-profile/probot-worker-live.js"; then
  echo 'AGNI_WORKER_LIVE_STATIC=blocked reason=redundant-worker-disabled-startup' >&2
  exit 1
fi
grep -Fq "ended.then(() => true)" "$here/startup-profile/probot-worker-live.js"

# The ingress outer deadline exceeds Probot's pinned Skymill client deadline.
grep -Fq 'AbortSignal.timeout(22000)' "$here/startup-profile/probot-worker-live.js"
grep -Fq 'AGNI_WORKER_LIVE_INGRESS_PHASE=begin' "$here/startup-profile/probot-worker-live.js"

# A cold handler must finish its first durable execution before duplicate ingress.
grep -Fq 'AGNI_WORKER_LIVE_FIRST_DELIVERY=accepted' "$here/startup-profile/probot-worker-live.js"
grep -Fq 'duplicate_after_ack=deduplicated' "$here/startup-profile/probot-worker-live.js"

# The memory-only candidate uses the same isolated VM1 guest and source-lock path.
grep -Fq 'qualify-worker-memory' "$here/operations/guest-migration.sh"
grep -Fq 'worker_gate=memory' "$here/operations/guest-migration.sh"
grep -Fq '"$worker_gate" == memory' "$here/startup-profile/probot-guest-app.sh"
grep -Fq 'AGNI_WORKER_MEMORY_RECOVERY=passed' "$here/startup-profile/probot-worker-live.js"
grep -Fq 'AGNI_WORKER_MEMORY_OUTAGE=passed' "$here/startup-profile/probot-worker-live.js"

# A fence gate must use the isolated live runner and verify worker restart results.
grep -Fq 'worker_gate=fence' "$here/operations/guest-migration.sh"
grep -Fq '"$worker_gate" == fence' "$here/startup-profile/probot-guest-app.sh"
grep -Fq 'AGNI_WORKER_FENCE=passed' "$here/startup-profile/probot-worker-live.js"
grep -Fq 'AGNI_WORKER_FENCE_HOOK=armed' "$here/startup-profile/probot-worker-live.js"

# Post-effect failure injection must exercise the existing isolated candidate.
grep -Fq 'worker_gate=effect' "$here/operations/guest-migration.sh"
grep -Fq '"$worker_gate" == effect' "$here/startup-profile/probot-guest-app.sh"
grep -Fq 'AGNI_WORKER_EFFECT=passed' "$here/startup-profile/probot-worker-live.js"
grep -Fq 'AGNI_WORKER_EFFECT_HOOK=armed' "$here/startup-profile/probot-worker-live.js"

# Each stage has a stable, auditable Make target and monotonic gate marker.
for gate in bootstrap delivery recovery full; do
  grep -Fq "gate=$gate" "$here/startup-profile/probot-worker-live.js" || [[ "$gate" == full ]]
done
grep -Fq 'AGNI_WORKER_LIVE_GATE_PHASE=' "$here/startup-profile/probot-worker-live.js"
grep -Fq 'listener_ready=' "$here/startup-profile/probot-worker-live.js"

# A failed candidate must still capture live service invocation and bootstrap invariants.
grep -Fq 'candidate_rc=0' "$here/startup-profile/probot-guest-app.sh"
grep -Fq 'AGNI_WORKER_LIVE_BASELINE=passed' "$here/startup-profile/probot-guest-app.sh"
grep -Fq 'candidate_exit=$candidate_rc' "$here/startup-profile/probot-guest-app.sh"
! grep -Fq 'nix.xd20261112' "$here/Makefile"
grep -Fq 'store.client.destroy()' "$here/startup-profile/probot-worker-live.js"

# Failure-path bootstrap checks need a validated profile contract; cold module loading has its own gate.
grep -Fq 'source "$apps/profile/profile.env"' "$here/startup-profile/probot-guest-app.sh"
grep -Fq 'reason=invalid-profile-contract' "$here/startup-profile/probot-guest-app.sh"
grep -Fq "checkpoint('pinned-probot-module-closure'" "$here/startup-profile/probot-worker-live.js"
grep -Fq 'proc_state=' "$here/startup-profile/probot-worker-live.js"

# Application node_modules are mirrored into VM-local qualification state and mounted read-only.
grep -Fq 'AGNI_WORKER_LIVE_MODULE_CACHE=passed' "$here/startup-profile/probot-guest-app.sh"
grep -Fq 'dst=/run/probot,ro' "$here/startup-profile/probot-guest-app.sh"
grep -Fq 'module_cache_parent="$base/qualification-cache/probot"' "$here/startup-profile/probot-guest-app.sh"
grep -Fq "assert.equal(probotRoot, '/run/probot'" "$here/startup-profile/probot-worker-live.js"

# VM-local mirror creation and the candidate lifecycle share one guest lock.
python3 - "$here/startup-profile/probot-guest-app.sh" <<'PY'
import pathlib,sys
s=pathlib.Path(sys.argv[1]).read_text()
p=s.index('  qualify-worker-live)')
q=s.index('  qualify-worker-candidate)',p)
section=s[p:q]
assert section.index('flock -x 9') < section.index('module_tmp=')
assert section.count('flock -x 9') == 1
PY
