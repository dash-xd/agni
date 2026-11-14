#!/usr/bin/env python3
"""Capture immutable stopped-guest overlays only after verified clean shutdown."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

import binding
import migration

ROOT = Path(__file__).resolve().parent
SHUTDOWN_MARKERS = ("Powering off.", "Reached target System Power Off.",
                    "Reached target Power-Off.")


def call(*args):
    result = subprocess.run(args, text=True, capture_output=True, timeout=45, check=False)
    if result.returncode:
        raise ValueError(args[0] + " failed: " + result.stderr[-250:])
    return result.stdout.strip()


def digest(path):
    value = hashlib.sha256()
    with open(path, "rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def inspect_stopped(machine, placement, state, artifact_state):
    name = placement["container"]
    details = json.loads(call("podman", "--connection", machine, "inspect", name))
    if len(details) != 1:
        raise ValueError("Expected exactly one stopped managed QEMU runner")
    item = details[0]
    if item.get("State", {}).get("Running") or item.get("State", {}).get("Status") != "exited":
        raise ValueError(name + " is not stopped; refusing a live QCOW2 copy")
    if item.get("State", {}).get("ExitCode") != 0 or item.get("State", {}).get("OOMKilled"):
        raise ValueError(name + " QEMU did not exit normally")
    manifest = migration.manifest(state / "manifest.txt")
    if manifest.get("container_id") != item.get("Id") or manifest.get("port") != str(placement["sshPort"]):
        raise ValueError(name + " managed container identity mismatch")
    if manifest.get("runner") is None or not manifest["runner"].startswith("sha256:"):
        raise ValueError(name + " missing recorded runner identity")
    disk = migration.regular(state / "overlay.qcow2")
    base = migration.regular(artifact_state / "base.qcow2")
    build = migration.manifest(state / "build.txt")
    if (manifest["runner"] != build.get("runner")
            or digest(base) != build.get("disk_sha256")):
        raise ValueError(name + " backing image digest mismatch")
    if disk.stat().st_size == 0:
        raise ValueError(name + " overlay is empty")
    serial = migration.regular(state / "serial.log").read_text(errors="replace")
    # An isolated log marker is not definitive evidence of an orderly current
    # shutdown. The marker must appear at the tail of the serial capture.
    tail = serial[-8192:]
    if not any(marker in tail for marker in SHUTDOWN_MARKERS):
        raise ValueError(name + " lacks a clean shutdown marker in serial tail")
    return {"name": name, "containerId": item["Id"],
            "exitCode": item["State"].get("ExitCode"),
            "overlay": str(disk), "base": str(base),
            "overlaySha256": digest(disk), "baseSha256": digest(base),
            "overlaySizeBytes": disk.stat().st_size,
            "serialSha256": digest(state / "serial.log"),
            "cleanShutdownMarker": True}


def backup():
    revision = os.environ.get("NIX_XD_SELECTED_PROJECT_REV", "")
    if not binding.SHA.fullmatch(revision):
        raise ValueError("Exact selected Agni revision required")
    if binding.run("git", "-C", str(ROOT.parents[1]), "rev-parse", "HEAD") != revision:
        raise ValueError("Selected Agni source revision changed")
    plan_bytes = (ROOT / "plan.json").read_bytes()
    plan = json.loads(plan_bytes)
    if set(plan["placements"]) != {"farcaster", "world1"}:
        raise ValueError("Unexpected one-Farcaster one-World topology")
    machine = os.environ.get("SHOAL_MACHINE", "coreos-arm64")
    if not machine.replace("-", "").replace("_", "").isalnum():
        raise ValueError("Invalid Podman connection")
    root = Path(os.environ.get("SHOAL_STATE_ROOT",
               str(Path.home() / ".local/state/nix-xd/coreos"))).expanduser().resolve()
    artifact = root / plan["placements"]["farcaster"]["instance"]
    states = {}
    for stage in ("farcaster", "world1"):
        placement = plan["placements"][stage]
        state = root / placement["instance"]
        states[stage] = inspect_stopped(machine, placement, state, artifact)
        print("AGNI_SHOAL_BACKUP_GUEST=stopped-and-inspected placement=" + stage, flush=True)
    if states["farcaster"]["baseSha256"] != states["world1"]["baseSha256"]:
        raise ValueError("Guests are not attached to the same qualified base image")
    destroot = Path(os.environ.get("SHOAL_BACKUP_ROOT",
               str(Path.home() / ".local/state/agni/shoal/backups"))).expanduser()
    destroot.mkdir(mode=0o700, parents=True, exist_ok=True)
    if destroot.is_symlink():
        raise ValueError("Unsafe backup root")
    size = sum(item["overlaySizeBytes"] for item in states.values())
    if shutil.disk_usage(destroot).free < size * 2:
        raise ValueError("Insufficient backup space")
    # Caller must have completed a clean guest shutdown. No process, network,
    # container, overlay, base, or original receipt is altered by this action.
    staging = Path(tempfile.mkdtemp(prefix=".shoal-backup-", dir=destroot))
    completed = False
    try:
        for stage, item in states.items():
            path = staging / stage
            path.mkdir(mode=0o700)
            guest_state = root / plan["placements"][stage]["instance"]
            for filename in ("overlay.qcow2", "manifest.txt", "build.txt",
                             "config.ign", "known_hosts"):
                original = migration.regular(guest_state / filename)
                shutil.copyfile(original, path / filename)
            if digest(path / "overlay.qcow2") != item["overlaySha256"]:
                raise ValueError("Overlay backup verification failed: " + stage)
        # Preserve backing bytes and provenance; restore must validate the backing path.
        shared = staging / "base.qcow2"
        shutil.copyfile(migration.regular(artifact / "base.qcow2"), shared)
        if digest(shared) != states["farcaster"]["baseSha256"]:
            raise ValueError("Backing image backup verification failed")
        receipt = {"schemaVersion": 1, "stage": "network-offline-backup",
                   "agniRevision": revision,
                   "planSha256": hashlib.sha256(plan_bytes).hexdigest(),
                   "machine": machine, "guests": states,
                   "backup": "sha256-verified-offline-copy",
                   "shutdownEvidence": "serial-log-tail-marker-only",
                   "network": "not-assessed", "egress": "not-assessed"}
        receipt_data = json.dumps(receipt, indent=2, sort_keys=True) + "\n"
        (staging / "receipt.json").write_text(receipt_data)
        destination = destroot / ("shoal-" + hashlib.sha256(receipt_data.encode()).hexdigest())
        if destination.exists():
            raise ValueError("Backup destination already exists; refusing overwrite")
        # No container can be restarted between the initial and final checks.
        for stage in ("farcaster", "world1"):
            item = states[stage]
            latest = json.loads(call("podman", "--connection", machine, "inspect", item["name"]))[0]
            if latest["Id"] != item["containerId"] or latest["State"]["Running"]:
                raise ValueError("Guest restarted during backup; refusing qualification")
            if digest(Path(item["overlay"])) != item["overlaySha256"]:
                raise ValueError("Original guest overlay changed during backup")
        staging.rename(destination)
        completed = True
        print("AGNI_SHOAL_BACKUP=passed path=" + str(destination), flush=True)
        print("AGNI_SHOAL_NETWORK=not-assessed", flush=True)
    finally:
        if not completed:
            shutil.rmtree(staging)


if __name__ == "__main__":
    try:
        backup()
    except (ValueError, OSError, KeyError, TypeError, json.JSONDecodeError,
            subprocess.SubprocessError, subprocess.TimeoutExpired) as exc:
        print("AGNI_SHOAL_BACKUP=blocked reason=" + str(exc), file=sys.stderr)
        sys.exit(1)
