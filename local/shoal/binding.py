#!/usr/bin/env python3
"""Read-only physical binding for the Agni-owned one-Farcaster/one-World plan."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent
PLAN = ROOT / "plan.json"
SHA = re.compile(r"[0-9a-f]{40}\Z")
CID = re.compile(r"[0-9a-f]{64}\Z")
BOOT = re.compile(r"[0-9a-f-]{36}\Z")


def run(*argv):
    result = subprocess.run(argv, text=True, capture_output=True, timeout=30, check=False)
    if result.returncode:
        raise ValueError(f"{argv[0]} failed ({result.returncode}): {result.stderr[-300:]}")
    return result.stdout.strip()


def inspect_binding(machine, container, port):
    result = json.loads(run("podman", "--connection", machine, "inspect", container))
    if not isinstance(result, list) or len(result) != 1:
        raise ValueError("Expected one QEMU runner")
    item = result[0]
    cid = item.get("Id", "")
    if not CID.fullmatch(cid) or not item.get("State", {}).get("Running"):
        raise ValueError("QEMU runner is not the expected running container")
    published = item.get("NetworkSettings", {}).get("Ports", {}).get("2222/tcp", [])
    if not any(entry.get("HostPort") == str(port) and
               entry.get("HostIp") in ("127.0.0.1", "::1")
               for entry in (published or [])):
        raise ValueError("Runner does not publish selected loopback SSH port")
    return cid


def bind(stage):
    if stage not in ("farcaster", "world1"):
        raise ValueError("Select farcaster or world1")
    raw = PLAN.read_bytes()
    plan = json.loads(raw)
    if plan.get("schemaVersion") != 1 or plan.get("name") != "shoal-one-world":
        raise ValueError("Unsupported Shoal plan")
    revision = os.environ.get("NIX_XD_SELECTED_PROJECT_REV", "")
    if not SHA.fullmatch(revision):
        raise ValueError("Exact selected Agni source revision required")
    source = ROOT.parents[1]
    if run("git", "-C", str(source), "rev-parse", "HEAD") != revision:
        raise ValueError("Selected Agni source moved")
    machine = os.environ.get("SHOAL_MACHINE", "coreos-arm64")
    if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_.-]{0,63}", machine):
        raise ValueError("Invalid Podman connection")
    state = Path(os.environ.get("SHOAL_STATE_ROOT",
                 str(Path.home() / ".local/state/nix-xd/coreos"))).expanduser().resolve()
    key = Path(os.environ.get("SHOAL_SSH_KEY",
               str(Path.home() / ".ssh/starwisp-test"))).expanduser().resolve()
    if not key.is_file():
        raise ValueError("Guest SSH key missing")
    entries = ("farcaster",) if stage == "farcaster" else ("farcaster", "world1")
    bindings = {}
    seen_cids = set()
    seen_boots = set()
    for name in entries:
        item = plan["placements"][name]
        instance, container = item["instance"], item["container"]
        port = item["sshPort"]
        if not re.fullmatch(r"[a-z][a-z0-9-]{0,63}", instance) or not 1024 <= port <= 65535:
            raise ValueError("Unsafe instance or port")
        known = state / instance / "known_hosts"
        if not known.is_file():
            raise ValueError(f"Missing pinned host identity for {name}: {known}")
        container_id = inspect_binding(machine, container, port)
        fingerprint = run("ssh-keygen", "-lf", str(known))
        boot_id = run("ssh", "-T", "-i", str(key), "-p", str(port),
                      "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes",
                      "-o", "StrictHostKeyChecking=yes",
                      "-o", "UserKnownHostsFile=" + str(known),
                      "-o", "ConnectTimeout=8",
                      item["sshUser"] + "@" + item["sshHost"],
                      "cat /proc/sys/kernel/random/boot_id")
        if not BOOT.fullmatch(boot_id):
            raise ValueError(f"Invalid boot ID for {name}")
        if container_id in seen_cids or boot_id in seen_boots:
            raise ValueError("Two logical placements resolve to the same physical VM")
        seen_cids.add(container_id)
        seen_boots.add(boot_id)
        bindings[name] = {
            "instance": instance, "container": container, "containerId": container_id,
            "sshHost": item["sshHost"], "sshPort": port, "sshUser": item["sshUser"],
            "knownHosts": str(known), "hostKeyFingerprints": fingerprint.splitlines(),
            "bootId": boot_id,
        }
    receipt = {
        "schemaVersion": 1, "stage": stage, "planId": plan["name"],
        "planSha256": hashlib.sha256(raw).hexdigest(), "agniRevision": revision,
        "machine": machine, "stateRoot": str(state), "bindings": bindings,
        "qualification": {"binding": "passed", "storage": "not-assessed",
                          "network": "not-assessed", "services": "not-assessed",
                          "endToEnd": "not-assessed"},
    }
    outdir = Path(os.environ.get("SHOAL_RECEIPT_ROOT",
                  str(Path.home() / ".local/state/agni/shoal/receipts"))).expanduser()
    outdir.mkdir(mode=0o700, parents=True, exist_ok=True)
    payload = json.dumps(receipt, sort_keys=True, indent=2) + "\n"
    digest = hashlib.sha256(payload.encode()).hexdigest()
    destination = outdir / (receipt["planSha256"] + "-" + revision + "-" +
                            stage + "-" + digest + ".json")
    with tempfile.NamedTemporaryFile(mode="w", dir=outdir, prefix=".binding-",
                                     delete=False) as handle:
        os.chmod(handle.name, 0o600)
        handle.write(payload)
        temporary = Path(handle.name)
    try:
        try:
            os.link(temporary, destination)
        except FileExistsError:
            if destination.read_text() != payload:
                raise ValueError("Existing binding receipt digest collision")
    finally:
        temporary.unlink(missing_ok=True)
    print(f"AGNI_SHOAL_BINDING=passed stage={stage} receipt={destination}")
    print("AGNI_SHOAL_APPLICATION=not-assessed")
    return receipt


if __name__ == "__main__":
    try:
        bind(os.environ.get("SHOAL_STAGE", "farcaster"))
    except (ValueError, OSError, KeyError, subprocess.SubprocessError, json.JSONDecodeError) as exc:
        print(f"AGNI_SHOAL_BINDING=blocked reason={exc}", file=sys.stderr)
        sys.exit(1)
