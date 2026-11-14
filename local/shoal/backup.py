#!/usr/bin/env python3
"""Read-only preflight for a future consistent, stopped-guest backup."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

import binding
import migration
import network

ROOT = Path(__file__).resolve().parent
CAPABILITY = ("busctl --system call org.freedesktop.login1 "
              "/org/freedesktop/login1 org.freedesktop.login1.Manager "
              "CanPowerOff")


def shutdown_permission(placement, known_hosts, key):
    ssh = ["ssh", "-T", "-i", str(key), "-p", str(placement["sshPort"]),
           "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes",
           "-o", "StrictHostKeyChecking=yes",
           "-o", "UserKnownHostsFile=" + str(known_hosts),
           "-o", "ConnectTimeout=8",
           placement["sshUser"] + "@" + placement["sshHost"], CAPABILITY]
    try:
        result = subprocess.run(ssh, capture_output=True, text=True, timeout=30)
    except subprocess.TimeoutExpired:
        return "unknown"
    if result.returncode:
        return "unknown"
    match = re.fullmatch(r's "(yes|no|challenge|na)"', result.stdout.strip())
    return match.group(1) if match else "unknown"


def inspect_state(stage, root, placement, boot):
    state = root / placement["instance"]
    build = migration.manifest(state / "build.txt")
    manifest = migration.manifest(state / "manifest.txt")
    overlay = migration.regular(state / "overlay.qcow2")
    if (manifest.get("container_id") != boot["containerId"]
            or manifest.get("port") != str(placement["sshPort"])):
        raise ValueError(stage + ": managed manifest no longer matches physical binding")
    if (build.get("disk_sha256") is None
            or build.get("runner") != manifest.get("runner")
            or build.get("shared_nix_volume") != "nix-xd-arm-store"):
        raise ValueError(stage + ": base image/runner/store provenance mismatch")
    if overlay.stat().st_size <= 0:
        raise ValueError(stage + ": empty overlay")
    return {
        "overlay": str(overlay),
        "overlaySizeBytes": overlay.stat().st_size,
        "baseDiskSha256": build["disk_sha256"],
        "runner": build["runner"],
        "manifestContainerId": manifest["container_id"],
        "bootId": boot["bootId"],
    }


def qualify():
    revision = os.environ.get("NIX_XD_SELECTED_PROJECT_REV", "")
    if not binding.SHA.fullmatch(revision):
        raise ValueError("Exact Agni revision required")
    if binding.run("git", "-C", str(ROOT.parents[1]), "rev-parse", "HEAD") != revision:
        raise ValueError("Source revision changed")
    plan = json.loads((ROOT / "plan.json").read_text())
    if set(plan["placements"]) != {"farcaster", "world1"}:
        raise ValueError("Unexpected topology")
    binding_receipt = binding.bind("world1")
    state = Path(binding_receipt["stateRoot"])
    key = migration.regular(Path(os.environ.get(
        "SHOAL_SSH_KEY", str(Path.home() / ".ssh/starwisp-test"))).expanduser())
    backup_root = Path(os.environ.get(
        "SHOAL_BACKUP_ROOT", str(Path.home() / ".local/state/agni/shoal/backups"))).expanduser()
    if backup_root.exists() and (backup_root.is_symlink() or not backup_root.is_dir()):
        raise ValueError("Unsafe backup destination")
    target_parent = backup_root if backup_root.exists() else backup_root.parent
    while not target_parent.exists():
        target_parent = target_parent.parent
    if target_parent.is_symlink() or not target_parent.is_dir():
        raise ValueError("Unsafe backup parent")
    disk = shutil.disk_usage(target_parent)
    observations = {}
    total_size = 0
    for stage in ("farcaster", "world1"):
        placement = plan["placements"][stage]
        boot = binding_receipt["bindings"][stage]
        observed = inspect_state(stage, state, placement, boot)
        observed["shutdownAuthorization"] = shutdown_permission(
            placement, state / placement["instance"] / "known_hosts", key)
        observations[stage] = observed
        total_size += observed["overlaySizeBytes"]
        print("AGNI_SHOAL_BACKUP_GUEST=preflight-passed placement=" + stage
              + " shutdown_authorization=" + observed["shutdownAuthorization"], flush=True)
    # Copying a stopped overlay still requires a stable immutable backing base.
    # The gate is conservative about on-disk capacity and does not initiate
    # shutdown or imply a filesystem-consistent backup has happened.
    enough_space = disk.free > total_size * 2
    result = {
        "schemaVersion": 1, "stage": "network-backup-preflight",
        "agniRevision": revision, "machine": binding_receipt["machine"],
        "observations": observations,
        "backupPath": str(backup_root),
        "capacity": {"freeBytes": disk.free, "overlayBytes": total_size,
                     "conservativeHeadroomAvailable": enough_space},
        "qualification": {"shutdown": "not-attempted",
                          "backup": "not-created",
                          "network": "not-assessed"},
    }
    print("AGNI_SHOAL_BACKUP_PREFLIGHT=" + ("passed" if enough_space else "blocked")
          + " free_bytes=" + str(disk.free)
          + " overlay_bytes=" + str(total_size), flush=True)
    for stage in ("farcaster", "world1"):
        if observations[stage]["shutdownAuthorization"] != "yes":
            print("AGNI_SHOAL_GRACEFUL_SHUTDOWN=unqualified placement=" + stage, flush=True)
    print("AGNI_SHOAL_BACKUP=not-created", flush=True)
    print("AGNI_SHOAL_NETWORK=not-assessed", flush=True)
    if not enough_space:
        raise ValueError("Insufficient conservative backup headroom")
    # Explicitly print machine-readable JSON, without writing outside logs.
    print("AGNI_SHOAL_BACKUP_PREFLIGHT_JSON=" + json.dumps(result, sort_keys=True), flush=True)


if __name__ == "__main__":
    try:
        qualify()
    except (ValueError, OSError, KeyError, TypeError, subprocess.SubprocessError,
            json.JSONDecodeError) as exc:
        print("AGNI_SHOAL_BACKUP_PREFLIGHT=blocked reason=" + str(exc), file=sys.stderr)
        sys.exit(1)
