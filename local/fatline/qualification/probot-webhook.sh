#!/usr/bin/env bash
set -Eeuo pipefail

scenario= phase=preflight
while (($#)); do
  case "$1" in
    --scenario)
      (($# >= 2)) || exit 2
      scenario=$2
      shift 2
      ;;
    --phase)
      (($# >= 2)) || exit 2
      phase=$2
      shift 2
      ;;
    *)
      printf 'Unknown Probot integration argument: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done
[[ "$scenario" == probot-webhook ]] || { echo 'Select --scenario probot-webhook' >&2; exit 2; }
[[ "$phase" == preflight || "$phase" == live ]] || { echo 'Select --phase preflight|live' >&2; exit 2; }

[[ "$(uname -s)" == Linux && "$(uname -m)" == aarch64 ]] || {
  echo 'PROBOT_WEBHOOK=blocked reason=requires-arm64-nix-alpine' >&2
  exit 1
}
: "${AGNI_PROBOT_SOURCES:?Set an immutable Nix-store source manifest}"
[[ -r "$AGNI_PROBOT_SOURCES" ]] || exit 1
source_root="${NIX_XD_PROBOT_WORKSPACES:-/workspaces}"
[[ "$source_root" == /workspaces ]] || {
  echo 'Nix-Alpine source root must be /workspaces' >&2
  exit 2
}

python3 - "$AGNI_PROBOT_SOURCES" "$source_root" <<'PY'
import json
import pathlib
import re
import sys

manifest = json.loads(pathlib.Path(sys.argv[1]).read_text())
if manifest.get("schema") != 1 or manifest.get("scenario") != "probot-webhook":
    raise SystemExit("Unsupported Probot webhook source selection")
sources = manifest["sources"]
if set(sources) != {"probot-runtime", "skymill", "logma"}:
    raise SystemExit("Incomplete component source selection")
for component, spec in sources.items():
    if not re.fullmatch(r"[0-9a-f]{40}", spec["revision"]):
        raise SystemExit(f"Invalid source revision for {component}")
    checkout = spec["checkout"]
    if not re.fullmatch(r"[a-z][a-z0-9-]{1,63}", checkout):
        raise SystemExit(f"Invalid staged checkout for {component}")
    directory = pathlib.Path(sys.argv[2]) / checkout
    marker = directory / ".nix-xd-source-revision"
    if not marker.is_file() or marker.read_text().strip() != spec["revision"]:
        raise SystemExit(f"Staged source mismatch for {component}: {checkout}")
    print(f"AGNI_PROBOT_SOURCE=passed component={component} sha={spec['revision']}")
if manifest.get("durability") != "skymill" or manifest.get("hints") != "logma":
    raise SystemExit("Durable provenance and hint authority contract changed")
if set(manifest.get("observers", [])) != {"logmash", "serverless-sse"}:
    raise SystemExit("Expected exactly two hint observers")
print("AGNI_PROBOT_SOURCE_SELECTION=passed system=aarch64-linux")
PY

probot_checkout="$(python3 - "$AGNI_PROBOT_SOURCES" <<'PY'
import json,sys
entry=json.load(open(sys.argv[1]))["sources"]["probot-runtime"]
print(entry["checkout"])
PY
)"
[[ "$probot_checkout" =~ ^[a-z][a-z0-9-]{1,63}$ ]] || exit 2
probot_root="$source_root/$probot_checkout"
[[ -f "$probot_root/src/skymill.js" && -f "$probot_root/test/skymill.test.js" ]] || exit 1
(
  cd "$probot_root"
  node --test test/skymill.test.js test/logma.test.js
)
echo 'AGNI_PROBOT_SKYMILL_CLIENT=passed durable_delivery_id=opaque logma=best-effort'
if [[ "$phase" == preflight ]]; then
  echo 'AGNI_PROBOT_WEBHOOK_PREFLIGHT=passed'
  echo 'AGNI_PROBOT_WEBHOOK_INTEGRATION=pending phase=arm64-provider-artifact-and-live-service-composition'
  exit 0
fi
echo 'AGNI_PROBOT_WEBHOOK_INTEGRATION=blocked phase=live scenario-not-yet-wired' >&2
exit 1
