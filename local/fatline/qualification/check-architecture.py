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
check("architecture-audit" in make, "missing-host-exception-inventory")
check("TARGET='#architecture-check'" in make, "smoke-not-in-nix-alpine")
check("include operations/deployment-compat.mk" in make, "legacy-deployment-not-isolated")
check("guest qualify-worker-live factory-live" in host, "factory-gate-not-from-agni")
check("xd_make guest-app FLAKE=" in host, "guest-not-generic-transport")
check("PROJECT=smoke20261112 APPLICATION=ghxd ACTION=source-sync" in host,
      "untracked-transitional-ghxd")
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
                        if "printf " in line and '".source-revision"' in line), "")
check(revision_record.count(chr(92)) == 1, "factory-revision-not-newline")
check('store_root="$root/$(basename "$artifact")"' in artifact,
      "factory-gc-root-not-content-addressed")
check("${artifact##*/}" not in artifact, "unescaped-nix-shell-interpolation")

legacy = re.findall(r"^deployment-([a-z][a-z0-9-]*):", make, re.M)
check(all(name.startswith(("qualify-", "seed-", "migrate-", "refresh-", "recover-",
                            "assess", "verify", "review", "diagnose-")) for name in legacy),
      "unexpected-deployment-dispatch")
print("AGNI_ARCHITECTURE_CHECK=passed composition=agni transport=nix-xd tools=smoke legacy_host=declared production=unchanged")
