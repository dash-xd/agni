#!/usr/bin/env python3
"""Architecture admission checks, distinct from VM1 live acceptance."""
from pathlib import Path
import json
import re

fatline = Path(__file__).resolve().parents[1]
make = (fatline / "Makefile").read_text()
host = (fatline / "operations/guest-migration.sh").read_text()
flake = (fatline / "flake.nix").read_text()
guest = (fatline / "startup-profile/probot-guest-app.sh").read_text()
worker = (fatline / "startup-profile/probot-worker-live.js").read_text()
policy = (fatline / "qualification/architecture-v20261115.md").read_text()
manifest = json.loads((fatline / "qualification/probot-factory-ghxd-sources.json").read_text())

def check(value, reason):
    if not value:
        raise SystemExit(f"AGNI_ARCHITECTURE_CHECK=failed reason={reason}")

check("Nix-Alpine pinned Agni flake" in policy, "missing-execution-policy")
check("host Podman operator" in policy, "host-exception-not-disclosed")
check("application-specific nix.xd" in policy, "nix-owner-boundary-missing")
check("make qualification QUALIFICATION=" in policy, "missing-canonical-entry")
check("qualification:" in make, "no-qualification-entry")
check("check-architecture:" in make, "no-architecture-check")
check("architecture-qualify:" in make, "no-cross-repo-admission-gate")
check("architecture-verify-sources:" in make, "source-lock-check-missing")
check("architecture-qualify: qualification-check architecture-verify-sources" in make,
      "architecture-does-not-check-source-lock")
locks = json.loads((fatline / "qualification/architecture-sources.json").read_text())
check(locks.get("schema") == 1 and set(locks.get("sources", {})) == {"nix-xd", "smoke"},
      "invalid-architecture-source-lock")
check(all(re.fullmatch(r"[0-9a-f]{40}", item.get("revision", ""))
          for item in locks["sources"].values()), "architecture-source-not-pinned")
check("architecture-audit" in make, "missing-host-exception-inventory")
check("TARGET='#architecture-check'" in make, "smoke-not-in-nix-alpine")
compat_path = fatline / "operations/deployment-compat.mk"
if compat_path.exists():
    check("include operations/deployment-compat.mk" in make, "legacy-deployment-not-isolated")
else:
    check("include operations/deployment-compat.mk" not in make,
          "orphaned-deployment-compat-include")
native = (fatline / "operations/native-source-sync.sh").read_text()
check("source-sync-native" in make, "native-ghxd-not-selectable")
check("TARGET='#ghxd-native'" in native, "native-ghxd-not-running-in-nix-alpine")
check("GHXD_NATIVE_GRANTS_ACK" in native, "unapproved-ghxd-secret-grants")
check('nix_make grants-plan GRANTS_FILE="$grants"' in native,
      "native-ghxd-grants-not-planned")
check('nix_make grants-verify GRANTS_FILE="$grants"' in native,
      "native-ghxd-must-check-live-grants")
check("AGNI_NATIVE_SOURCE_SYNC=passed" in native, "native-ghxd-result-not-contractual")
check("podman " not in native, "agni-reintroduced-host-podman-orchestration")
check("guest qualify-worker-live factory-live" in host, "factory-gate-not-from-agni")
check("xd_make guest-app FLAKE=" in host, "guest-not-generic-transport")
check('NIX_XD_DIR ?=' in make, "implicit-stale-nix-xd-checkout")
check('PROVIDER ?= podman' in make, "wrong-provider-default")
check("AGNI_WORKER_LIVE_BASELINE=passed" in guest, "no-baseline-invariant")
check("AGNI_FACTORY_LIVE_PREFLIGHT=passed" in guest, "no-artifact-identity-check")
check("AGNI_PROBOT_FACTORY_LIVE=passed" in worker, "no-live-result-contract")
check("AGNI_PROBOT_FACTORY_RECOVERY=passed" in worker, "no-recovery-contract")

pinned = manifest.get("sources", {}).get("probot-factory", {})
revision = pinned.get("revision", "")
check(re.fullmatch(r"[0-9a-f]{40}", revision) is not None,
      "factory-revision-not-sha")
check(pinned.get("repository") == "xd-dash/probot-runtime",
      "factory-owner-drift")
check(f'probotFactoryRevision = "{revision}";' in flake,
      "manifest-flake-source-pin-mismatch")
check("source=${probotFactoryCheckout}" in flake, "factory-not-staged-from-checkout")

artifact = flake.split("subscription-factory-source-artifact = {", 1)[1].split(
    "subscription-groups-source-artifact = {", 1
)[0]
revision_record = next((line for line in artifact.splitlines()
                        if "printf " in line and ".source-revision" in line), "")
check(revision_record.count(chr(92)) == 1, "factory-revision-not-newline")
check('store_root="$root/$(basename "$artifact")"' in artifact,
      "factory-gc-root-not-content-addressed")
check("${artifact##*/}" not in artifact, "unescaped-nix-shell-interpolation")

if compat_path.exists():
    compat = compat_path.read_text()
    legacy = re.findall(r"^deployment-([a-z][a-z0-9-]*):", compat, re.M)
    check(all(name.startswith(("qualify-", "seed-", "migrate-", "refresh-", "recover-",
                                "assess", "verify", "review", "diagnose-")) for name in legacy),
          "unexpected-deployment-dispatch")
canonical = (fatline / "qualification/CANONICAL-ARCHITECTURE.md").read_text()
agents = (fatline.parents[1] / "AGENTS.md").read_text()
for phrase in ("Deny old idioms", "Ordered gates", "source-sync-native",
               "factory-live", "systemd/Quadlet lifecycle", "boot ID"):
    check(phrase in canonical, "missing-canonical-contract-" + phrase.replace(" ", "-"))
check("qualification/CANONICAL-ARCHITECTURE.md" in agents,
      "agent-contract-not-linked")
check("Do not add new" in agents and "quarantined exceptions" in agents,
      "legacy-route-not-banned")
print("AGNI_ARCHITECTURE_CHECK=passed composition=agni transport=nix-xd tools=smoke legacy_host=declared production=unchanged")
