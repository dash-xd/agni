#!/usr/bin/env python3
"""Prepare a private rollback baseline and deployment intent; never activate."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import tempfile

SCOPE = "fatline-arm-vm1"
ROLES = ("redis", "nginx", "logma", "skymill")
FILENAME = re.compile(r"[a-zA-Z0-9._-]+")
SHA = re.compile(r"[a-f0-9]{64}")


def file_copy(source, dest):
    if source.is_symlink() or not source.is_file():
        raise ValueError("Snapshot source must be a regular file: " + str(source))
    dest.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    with source.open("rb") as source_file, dest.open("xb") as output:
        shutil.copyfileobj(source_file, output)
    dest.chmod(0o600)
    return hashlib.sha256(dest.read_bytes()).hexdigest()


def snapshot(source, output, files, checksums):
    for relative in files:
        origin = source / relative
        if not origin.is_file():
            raise ValueError("Missing rollback input: " + str(relative))
        checksums[str(relative)] = file_copy(origin, output / relative)


def credentials(source, output, checksums):
    for role in ("logma", "skymill", "bootstrap"):
        directory = source / role
        if directory.is_symlink() or not directory.is_dir():
            raise ValueError("Missing private credential directory: " + role)
        entries = sorted(directory.iterdir())
        if not entries:
            raise ValueError("Empty credential directory: " + role)
        for entry in entries:
            if not FILENAME.fullmatch(entry.name):
                raise ValueError("Unexpected credential filename")
            checksums[str(Path(role) / entry.name)] = file_copy(entry, output / role / entry.name)


def prepare(migration, assessment_path, installed_units, base, output, generation, boot_id, invocations):
    assessment_bytes = assessment_path.read_bytes()
    digest = hashlib.sha256(assessment_bytes).hexdigest()
    assessment = json.loads(assessment_bytes)
    if assessment.get("scope") != SCOPE or assessment.get("activation") != "blocked":
        raise ValueError("Invalid migration assessment")
    if assessment.get("status") != "legacy-profile-migration-required":
        raise ValueError("Existing deployment must be legacy")
    expected = digest + "-" + assessment["bundle"].split("/")[-1]
    if generation != expected or not re.fullmatch(r"[a-f0-9]{64}-[a-z0-9]{32}-candidate", generation):
        raise ValueError("Unexpected staged generation")
    if not re.fullmatch(r"[a-f0-9-]{36}", boot_id):
        raise ValueError("Invalid guest boot identity")
    if set(invocations) != set(ROLES) or any(not re.fullmatch(r"[a-f0-9]{32}", value) for value in invocations.values()):
        raise ValueError("Complete running systemd invocation IDs required")
    baseline = assessment.get("quadlets", {})
    for role in ROLES:
        filename = SCOPE + "-" + role + ".container"
        file = installed_units / filename
        if file.is_symlink() or not file.is_file() or hashlib.sha256(file.read_bytes()).hexdigest() != baseline[role]["sha256"]:
            raise ValueError("Legacy Quadlet changed: " + role)
    if (installed_units / (SCOPE + "-probot.container")).exists():
        raise ValueError("Probot is no longer a staged-only role")
    acl = base / "credentials/users.acl"
    if hashlib.sha256(acl.read_bytes()).hexdigest() != assessment["acl"]["sha256"]:
        raise ValueError("Legacy ACL changed since assessment")
    for item in ("rendered/manifest.json", "rendered/users.acl", "rendered/profile.env"):
        if not (migration / item).is_file():
            raise ValueError("Incomplete new generation")
    if output.exists():
        raise ValueError("Activation plan already exists; do not overwrite or rotate private baseline")
    output.parent.mkdir(parents=True, mode=0o700, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".activation-", dir=output.parent) as temp:
        work = Path(temp)
        work.chmod(0o700)
        rollback = work / "rollback"
        rollback.mkdir(mode=0o700)
        checksums = {"quadlets": {}, "config": {}, "credentials": {}}
        units = [Path(SCOPE + "-" + role + ".container") for role in ROLES]
        units.append(Path(SCOPE + ".network"))
        snapshot(installed_units, rollback / "quadlets", units, checksums["quadlets"])
        for role in ROLES:
            dropins = installed_units / (SCOPE + "-" + role + ".container.d")
            if dropins.is_symlink():
                raise ValueError("Symlinked legacy Quadlet drop-in directory")
            if dropins.exists():
                if not dropins.is_dir():
                    raise ValueError("Invalid legacy Quadlet drop-in directory")
                for file in sorted(dropins.iterdir()):
                    if not FILENAME.fullmatch(file.name):
                        raise ValueError("Unexpected legacy Quadlet drop-in filename")
                    relative = Path(dropins.name) / file.name
                    checksums["quadlets"][str(relative)] = file_copy(file, rollback / "quadlets" / relative)
        required_config = [Path("credentials/users.acl"), Path("config/redis.conf"),
                           Path("config/nginx.conf")]
        snapshot(base, rollback / "config", required_config, checksums["config"])
        optional_config = [Path("services/bootstrap-template.acl"), Path("services/boot-wait.sh")]
        absent_optional = []
        for relative in optional_config:
            source = base / relative
            if source.is_symlink():
                raise ValueError("Symlinked optional rollback input: " + str(relative))
            if source.exists():
                checksums["config"][str(relative)] = file_copy(source, rollback / "config" / relative)
            else:
                absent_optional.append(str(relative))
        credentials(base / "services/credentials", rollback / "credentials", checksums["credentials"])
        candidate_acl = hashlib.sha256((migration / "rendered/users.acl").read_bytes()).hexdigest()
        manifest = json.loads((migration / "rendered/manifest.json").read_text())
        if manifest["aclDigest"] != candidate_acl:
            raise ValueError("Target ACL digest mismatch")
        plan = {
            "schema": 1, "kind": "agni.deployment.activation-plan",
            "deployment": "vm1", "scope": SCOPE, "generation": generation,
            "assessment_sha256": digest,
            "target_acl_sha256": candidate_acl,
            "guest_boot_id": boot_id,
            "service_invocations": invocations,
            "legacy_store_references": {role: baseline[role].get("store_references", []) for role in ROLES},
            "rollback_checksums": checksums,
            "legacy_absent_optional_paths": absent_optional,
            "activation": {"allowed": False, "reason": "separate explicit activation authorization required",
                           "state": "planned-only", "operations_executed": []},
            "transition": [
                "require explicit operator approval for Redis RAM-only stream loss",
                "verify baseline checksums and live service invocation IDs again",
                "stop dependent roles and Redis only after approval",
                "install target network, private credentials, configs and five Quadlets transactionally",
                "systemd user daemon-reload then start Redis with bootstrap gate",
                "verify Redis ACL/bootstrap, nginx, logma, skymill and probot readiness"
            ],
            "readiness": {"systemd": list(ROLES) + ["probot"],
                          "redis_bootstrap": "ready invocation matches active Redis service",
                          "applications": "strict application readiness endpoints must pass before success",
                          "probot": "real GitHub App/ingress secrets must be bound; worker remains disabled in staged candidate"},
            "rollback": {"prepared": True, "executed": False,
                         "procedure": ["stop candidate units", "restore snapshotted Quadlets, network, private credentials and config",
                                       "systemd user daemon-reload", "start legacy Redis and dependents", "verify legacy readiness"],
                         "redis_stream_data_recovered": False,
                         "legacy_store_roots": "must-remain-pinned-by-store-owner-through-rollback-window"},
            "data_loss": {"redis_persistence": "save-disabled;appendonly-disabled",
                          "restart_loses_ram_only_streams": True,
                          "rollback_does_not_restore_stream_data": True},
            "control": {"executor": "guest-local Agni operation",
                        "transport": "adapter-supplied; not bound to Mac, SSH or GCP"},
        }
        (work / "plan.json").write_text(json.dumps(plan, indent=2, sort_keys=True) + "\n")
        (work / "plan.json").chmod(0o600)
        work.rename(output)
    return plan


def main():
    parser = argparse.ArgumentParser()
    for name in ("migration", "assessment", "installed-units", "base", "output", "generation", "boot-id"):
        parser.add_argument("--" + name, required=True)
    for role in ROLES:
        parser.add_argument("--" + role + "-invocation", required=True)
    args = parser.parse_args()
    plan = prepare(Path(args.migration), Path(args.assessment), Path(args.installed_units),
                   Path(args.base), Path(args.output), args.generation, args.boot_id,
                   {role: getattr(args, role + "_invocation") for role in ROLES})
    print("AGNI_ACTIVATION_PLAN=passed roles=5 rollback=prepared redis_loss=explicit activation=blocked")


if __name__ == "__main__":
    main()
