#!/usr/bin/env python3
"""Read-only pre-activation gate for one staged Fatline generation."""
import argparse
import hashlib
import json
from pathlib import Path
import re

SCOPE = "fatline-arm-vm1"
ROLES = ("redis", "nginx", "logma", "skymill")
STORE = re.compile(r"/nix/store/[a-z0-9]{32}-[A-Za-z0-9._+-]+(?:/[A-Za-z0-9._+/-]+)?")
GENERATION = re.compile(r"[0-9a-f]{64}-[0-9a-z]{32}-candidate")
HEXDIGEST = re.compile(r"[0-9a-f]{64}")


def digest(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError("Missing or symlinked activation input: " + str(path))
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(plan_dir, migration, assessment_path, installed_units, base, store, boot_id, invocations):
    if plan_dir.is_symlink() or not plan_dir.is_dir() or not GENERATION.fullmatch(plan_dir.name):
        raise ValueError("Invalid private activation plan directory")
    if migration.name != plan_dir.name:
        raise ValueError("Selected generation changed")
    plan_path = plan_dir / "plan.json"
    if plan_path.stat().st_mode & 0o077 or plan_path.is_symlink():
        raise ValueError("Activation plan is not private")
    plan = json.loads(plan_path.read_bytes())
    if plan.get("schema") != 1 or plan.get("kind") != "agni.deployment.activation-plan":
        raise ValueError("Unexpected activation plan schema")
    if plan.get("deployment") != "vm1" or plan.get("scope") != SCOPE or plan.get("generation") != plan_dir.name:
        raise ValueError("Activation plan identity changed")
    if plan.get("activation", {}).get("allowed") is not False or plan["activation"].get("operations_executed") != []:
        raise ValueError("Activation is no longer blocked/untouched")
    if not plan.get("rollback", {}).get("prepared") or plan["rollback"].get("executed") is not False:
        raise ValueError("Rollback baseline was not marked unexecuted")
    if plan.get("guest_boot_id") != boot_id or plan.get("service_invocations") != invocations or set(invocations) != set(ROLES):
        raise ValueError("Live VM boot/service invocation changed since plan creation")
    assessment_hash = digest(assessment_path)
    if assessment_hash != plan.get("assessment_sha256"):
        raise ValueError("Original assessment changed")
    assessment = json.loads(assessment_path.read_text())
    if plan_dir.name != assessment_hash + "-" + assessment["bundle"].split("/")[-1]:
        raise ValueError("Assessment does not select this generation")
    checksums = plan["rollback_checksums"]
    mappings = {
        "quadlets": (installed_units, plan_dir / "rollback/quadlets"),
        "config": (base, plan_dir / "rollback/config"),
        "credentials": (base / "services/credentials", plan_dir / "rollback/credentials"),
    }
    required = {
        "quadlets": {SCOPE + "-" + role + ".container" for role in ROLES} | {SCOPE + ".network"},
        "config": {"credentials/users.acl", "config/redis.conf", "config/nginx.conf"},
        "credentials": {"logma/redis", "logma/api-key", "skymill/redis", "bootstrap/redis"},
    }
    for category, (current, snapshot) in mappings.items():
        entries = checksums[category]
        if not required[category] <= set(entries):
            raise ValueError("Rollback snapshot inventory incomplete: " + category)
        for relative, expected in entries.items():
            relative_path = Path(relative)
            if relative_path.is_absolute() or ".." in relative_path.parts or not HEXDIGEST.fullmatch(expected):
                raise ValueError("Invalid rollback checksum inventory")
            if digest(snapshot / relative_path) != expected:
                raise ValueError("Rollback snapshot modified: " + category + "/" + relative)
            if digest(current / relative_path) != expected:
                raise ValueError("Live baseline drift: " + category + "/" + relative)
    if (installed_units / (SCOPE + "-probot.container")).exists():
        raise ValueError("Target Probot unit unexpectedly installed")
    if (base / "services/profile/profile.env").exists():
        raise ValueError("Consolidated profile already installed")
    candidate_acl = digest(migration / "rendered/users.acl")
    if candidate_acl != plan.get("target_acl_sha256"):
        raise ValueError("Candidate ACL changed")
    for role in (*ROLES, "probot"):
        if not (migration / "rendered" / (SCOPE + "-" + role + ".container")).is_file():
            raise ValueError("Staged target Quadlet is missing: " + role)
    if not (migration / "rendered" / (SCOPE + ".network")).is_file():
        raise ValueError("Staged target network is missing")
    store_refs = plan.get("legacy_store_references", {})
    if set(store_refs) != set(ROLES):
        raise ValueError("Legacy store inventory incomplete")
    for role, refs in store_refs.items():
        if not refs:
            raise ValueError("Legacy role has no recorded store references: " + role)
        for value in refs:
            if not STORE.fullmatch(value):
                raise ValueError("Invalid legacy store path: " + role)
            guest = store / value.removeprefix("/nix/store/")
            if not guest.is_file():
                raise ValueError("Legacy executable unavailable: " + role)
    for field in ("redis_persistence", "restart_loses_ram_only_streams", "rollback_does_not_restore_stream_data"):
        if field not in plan["data_loss"]:
            raise ValueError("Missing Redis data loss contract")
    if not plan["data_loss"]["restart_loses_ram_only_streams"] or not plan["data_loss"]["rollback_does_not_restore_stream_data"]:
        raise ValueError("RAM-only stream-loss acknowledgement not recorded")
    # Planning cannot authorize a destructive activation or assert that the
    # application-level readiness/GitHub App credentials already exist.
    return {
        "generation": plan_dir.name,
        "eligible": False,
        "blocking": ["explicit-data-loss-authorization", "strict-readiness-fixtures",
                     "github-app-ingress-binding", "qualified-rollback-executor",
                     "legacy-nix-store-root-retention"],
    }


def main():
    parser = argparse.ArgumentParser()
    for name in ("plan-dir", "migration", "assessment", "installed-units", "base",
                 "store", "boot-id"):
        parser.add_argument("--" + name, required=True)
    for role in ROLES:
        parser.add_argument("--" + role + "-invocation", required=True)
    args = parser.parse_args()
    report = verify(
        Path(args.plan_dir), Path(args.migration), Path(args.assessment),
        Path(args.installed_units), Path(args.base), Path(args.store), args.boot_id,
        {role: getattr(args, role + "_invocation") for role in ROLES})
    print("AGNI_ACTIVATION_BASELINE=passed snapshot=verified live=unchanged legacy_store=visible")
    print("AGNI_ACTIVATION_CHECK=passed generation=" + report["generation"] +
          " readiness=blocked activation=blocked redis_restart=none")
    print("AGNI_ACTIVATION_BLOCKERS=" + ",".join(report["blocking"]))


if __name__ == "__main__":
    main()
