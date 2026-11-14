#!/usr/bin/env python3
"""Verify archived Shoal backup integrity without restoring or touching guests."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

import binding
import migration

ROOT = Path(__file__).resolve().parent
STAGES = ("farcaster", "world1")
FILES = ("overlay.qcow2", "manifest.txt", "build.txt", "config.ign", "known_hosts")


def sha256(path):
    h = hashlib.sha256()
    with migration.regular(path).open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def verify(path, plan_digest):
    if path.is_symlink() or not path.is_dir():
        raise ValueError("Missing or unsafe backup directory")
    receipt_bytes = migration.regular(path / "receipt.json").read_bytes()
    receipt_hash = hashlib.sha256(receipt_bytes).hexdigest()
    if path.name != "shoal-" + receipt_hash:
        raise ValueError("Backup directory name differs from receipt SHA256")
    receipt = json.loads(receipt_bytes)
    if receipt.get("schemaVersion") != 1 or receipt.get("stage") != "network-offline-backup":
        raise ValueError("Unrecognized backup receipt")
    if receipt.get("planSha256") != plan_digest or set(receipt.get("guests", {})) != set(STAGES):
        raise ValueError("Backup topology or source plan mismatch")
    base_hash = sha256(path / "base.qcow2")
    result = {}
    for name in STAGES:
        guest = receipt["guests"][name]
        directory = path / name
        if directory.is_symlink() or not directory.is_dir():
            raise ValueError("Missing safe guest backup directory")
        for filename in FILES:
            migration.regular(directory / filename)
        overlay = directory / "overlay.qcow2"
        if sha256(overlay) != guest.get("overlaySha256"):
            raise ValueError(name + ": overlay SHA256 mismatch")
        if overlay.stat().st_size != guest.get("overlaySizeBytes"):
            raise ValueError(name + ": overlay size mismatch")
        if guest.get("baseSha256") != base_hash:
            raise ValueError(name + ": archived base SHA256 mismatch")
        build = migration.manifest(directory / "build.txt")
        manifest = migration.manifest(directory / "manifest.txt")
        if (build.get("disk_sha256") != base_hash
                or manifest.get("runner") != build.get("runner")
                or manifest.get("container_id") != guest.get("containerId")):
            raise ValueError(name + ": archive provenance mismatch")
        result[name] = {"overlaySha256": guest["overlaySha256"],
                        "baseSha256": base_hash, "backingPathQualified": False}
    return {"receiptSha256": receipt_hash, "guests": result,
            "archiveIntegrity": "passed", "restoreBoot": "not-qualified"}


def main():
    revision = os.environ.get("NIX_XD_SELECTED_PROJECT_REV", "")
    if not binding.SHA.fullmatch(revision) or binding.run(
            "git", "-C", str(ROOT.parents[1]), "rev-parse", "HEAD") != revision:
        raise ValueError("Exact Agni revision required")
    value = os.environ.get("SHOAL_BACKUP_PATH")
    if not value:
        raise ValueError("Explicit SHOAL_BACKUP_PATH required")
    backup = Path(value).expanduser().absolute()
    root = Path(os.environ.get("SHOAL_BACKUP_ROOT",
        str(Path.home() / ".local/state/agni/shoal/backups"))).expanduser().resolve()
    if backup.parent != root:
        raise ValueError("Backup must be immediately inside managed backup root")
    report = verify(backup, hashlib.sha256((ROOT / "plan.json").read_bytes()).hexdigest())
    print("AGNI_SHOAL_BACKUP_VERIFY=passed path=" + str(backup), flush=True)
    print("AGNI_SHOAL_ROLLBACK=not-qualified", flush=True)
    print("AGNI_SHOAL_BACKUP_VERIFY_JSON=" + json.dumps(report, sort_keys=True), flush=True)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, TypeError, subprocess.SubprocessError,
            json.JSONDecodeError) as exc:
        print("AGNI_SHOAL_BACKUP_VERIFY=blocked reason=" + str(exc), file=sys.stderr)
        sys.exit(1)
