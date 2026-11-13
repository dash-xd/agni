#!/usr/bin/env python3
"""Shoal-owned World 1 lifecycle adapter over the generic Nix-Alpine host dispatcher."""
import json
import os
from pathlib import Path
import subprocess
import sys

import binding

ROOT = Path(__file__).resolve().parent
VM = ROOT.parent / "vm" / "coreos-podman.sh"


def execute(action):
    if action not in ("ignition", "preflight", "start"):
        raise ValueError("Unsupported World 1 lifecycle action")
    revision = os.environ.get("NIX_XD_SELECTED_PROJECT_REV", "")
    if not binding.SHA.fullmatch(revision):
        raise ValueError("Exact Agni revision required")
    if binding.run("git", "-C", str(ROOT.parents[1]), "rev-parse", "HEAD") != revision:
        raise ValueError("Selected Agni source revision changed")
    plan = json.loads((ROOT / "plan.json").read_text())
    farcaster = plan["placements"]["farcaster"]
    world = plan["placements"]["world1"]
    if world["instance"] == farcaster["instance"] or world["container"] == farcaster["container"] or world["sshPort"] == farcaster["sshPort"]:
        raise ValueError("World 1 must be physically independent of Farcaster")
    if world["instance"] != "shoal-world1":
        raise ValueError("Unexpected selected World 1 image profile")
    if plan["sharedStore"]["mode"] != "read-only" or plan["sharedStore"]["guestProtocol"] != "9p":
        raise ValueError("World 1 must consume the host-owned 9P store")
    state_root = Path(os.environ.get("SHOAL_STATE_ROOT", str(Path.home() / ".local/state/nix-xd/coreos"))).expanduser().resolve()
    farcaster_state = state_root / farcaster["instance"]
    if not (farcaster_state / "build.txt").is_file() or not (farcaster_state / "base.qcow2").is_file():
        raise ValueError("Qualified Farcaster base artifacts are missing")
    env = os.environ.copy()
    env.update({
        "COREOS_PROFILE": world["instance"],
        "COREOS_STATE_ROOT": str(state_root),
        "COREOS_ARTIFACT_STATE": str(farcaster_state),
        "COREOS_CONTAINER_NAME": world["container"],
        "COREOS_SSH_PORT": str(world["sshPort"]),
        "COREOS_NIX_STORE_VOLUME": plan["sharedStore"]["owner"] + "-store",
    })
    if action == "ignition":
        env["COREOS_SSH_PUBLIC_KEY"] = os.environ.get("SHOAL_SSH_PUBLIC_KEY",
                                               str(Path.home() / ".ssh/starwisp-test.pub"))
    print("AGNI_SHOAL_WORLD1_ACTION=" + action + " state=" + str(state_root / world["instance"]), flush=True)
    subprocess.run(["bash", str(VM), action], env=env, check=True)


if __name__ == "__main__":
    try:
        execute(os.environ.get("SHOAL_WORLD1_ACTION", "preflight"))
    except (ValueError, OSError, KeyError, subprocess.SubprocessError) as exc:
        print("AGNI_SHOAL_WORLD1=blocked reason=" + str(exc), file=sys.stderr)
        sys.exit(1)
