#!/usr/bin/env python3
"""Enroll a fresh World's SSH host key with an explicit SHA256 fingerprint confirmation."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

import binding

ROOT = Path(__file__).resolve().parent
PLAN = ROOT / "plan.json"


def collect(machine, port, container):
    container_id = binding.inspect_binding(machine, container, port)
    result = subprocess.run(["ssh-keyscan", "-T", "10", "-p", str(port),
                             "-t", "ed25519", "127.0.0.1"],
                            text=True, capture_output=True, timeout=25)
    lines = sorted(set(line.strip() for line in result.stdout.splitlines()
                       if line and not line.startswith("#")))
    if result.returncode or len(lines) != 1:
        raise ValueError("Expected exactly one World 1 ED25519 SSH host key")
    line = lines[0]
    if not line.startswith(f"[127.0.0.1]:{port} ssh-ed25519 "):
        raise ValueError("Host key is not scoped to the World 1 loopback port")
    with tempfile.NamedTemporaryFile(mode="w", delete=False) as handle:
        handle.write(line + "\n")
        temporary = Path(handle.name)
    try:
        fingerprint_line = binding.run("ssh-keygen", "-lf", str(temporary))
    finally:
        temporary.unlink(missing_ok=True)
    match = re.search(r"SHA256:[A-Za-z0-9+/]+", fingerprint_line)
    if not match:
        raise ValueError("Cannot read World 1 host key fingerprint")
    return container_id, line + "\n", match.group()


def execute(action):
    if action not in ("plan", "enroll"):
        raise ValueError("Select plan or enroll")
    revision = os.environ.get("NIX_XD_SELECTED_PROJECT_REV", "")
    if not binding.SHA.fullmatch(revision):
        raise ValueError("Exact Agni source revision required")
    if binding.run("git", "-C", str(ROOT.parents[1]), "rev-parse", "HEAD") != revision:
        raise ValueError("Selected Agni source revision changed")
    plan = json.loads(PLAN.read_text())
    world = plan["placements"]["world1"]
    if world["container"] != "coreos-shoal-world1" or world["sshPort"] != 2223:
        raise ValueError("Unexpected World 1 physical SSH contract")
    machine = os.environ.get("SHOAL_MACHINE", "coreos-arm64")
    state_root = Path(os.environ.get("SHOAL_STATE_ROOT",
                        str(Path.home() / ".local/state/nix-xd/coreos"))).expanduser().resolve()
    state = state_root / world["instance"]
    manifest = state / "manifest.txt"
    if not manifest.is_file():
        raise ValueError("World 1 managed QEMU manifest missing")
    cid, payload, fingerprint = collect(machine, world["sshPort"], world["container"])
    if "container_id=" + cid not in manifest.read_text().splitlines():
        raise ValueError("World 1 container does not match its managed manifest")
    farcaster = state_root / plan["placements"]["farcaster"]["instance"] / "known_hosts"
    if farcaster.is_file():
        old = binding.run("ssh-keygen", "-lf", str(farcaster))
        if fingerprint in old:
            raise ValueError("World 1 must have a distinct SSH host key")
    print("AGNI_SHOAL_WORLD1_HOSTKEY_FINGERPRINT=" + fingerprint, flush=True)
    print("AGNI_SHOAL_WORLD1_HOSTKEY_CONTAINER=" + cid, flush=True)
    if action == "plan":
        print("AGNI_SHOAL_WORLD1_HOSTKEY=untrusted-until-confirmed", flush=True)
        return
    confirmation = os.environ.get("SHOAL_WORLD1_HOSTKEY_CONFIRM", "")
    if confirmation != fingerprint:
        raise ValueError("Explicit fingerprint confirmation required; run hostkey-plan first")
    known = state / "known_hosts"
    known.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    if known.exists():
        if known.read_text() != payload:
            raise ValueError("Existing pinned host key differs; refusing overwrite")
    else:
        with tempfile.NamedTemporaryFile("w", dir=known.parent,
                                         prefix=".known_hosts-", delete=False) as handle:
            os.chmod(handle.name, 0o600)
            handle.write(payload)
            pending = Path(handle.name)
        try:
            os.link(pending, known)
        except FileExistsError:
            if known.read_text() != payload:
                raise ValueError("Conflicting World 1 host-key enrollment")
        finally:
            pending.unlink(missing_ok=True)
    print("AGNI_SHOAL_WORLD1_HOSTKEY=confirmed path=" + str(known), flush=True)
    print("AGNI_SHOAL_WORLD1_NETWORK=not-assessed", flush=True)


if __name__ == "__main__":
    try:
        execute(os.environ.get("SHOAL_HOSTKEY_ACTION", "plan"))
    except (ValueError, OSError, KeyError, subprocess.SubprocessError) as exc:
        print("AGNI_SHOAL_WORLD1_HOSTKEY=blocked reason=" + str(exc), file=sys.stderr)
        sys.exit(1)
