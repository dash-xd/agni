#!/usr/bin/env python3
"""Read-only prereconfiguration probe for the Shoal inter-VM network."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

import binding

ROOT = Path(__file__).resolve().parent
PLAN = ROOT / "plan.json"


def run(*argv, timeout=30):
    result = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        raise ValueError(f"{argv[0]} exit={result.returncode}: {result.stderr[-250:]}")
    return result.stdout.strip()


def inspect_runner(machine, placement, cid):
    raw = json.loads(run("podman", "--connection", machine, "inspect", placement["container"]))
    if len(raw) != 1 or raw[0].get("Id") != cid or not raw[0].get("State", {}).get("Running"):
        raise ValueError("Physical QEMU container changed since binding")
    item = raw[0]
    argv = item.get("Config", {}).get("Cmd", []) or []
    if not any("-netdev" == token for token in argv):
        raise ValueError("QEMU network arguments unavailable in managed runner")
    netdevs = [argv[i + 1] for i, token in enumerate(argv[:-1]) if token == "-netdev"]
    if netdevs != ["user,id=n0,hostfwd=tcp::2222-:22"]:
        raise ValueError("Unexpected existing guest network devices; refuse automated migration")
    return {"containerId": cid, "networkDevices": netdevs,
            "podmanNetworkMode": item.get("HostConfig", {}).get("NetworkMode", "")}


def guest_preflight(placement, known, key):
    ssh = ["ssh", "-T", "-i", str(key), "-p", str(placement["sshPort"]),
           "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes",
           "-o", "StrictHostKeyChecking=yes",
           "-o", "UserKnownHostsFile=" + str(known),
           "-o", "ConnectTimeout=8",
           placement["sshUser"] + "@" + placement["sshHost"]]
    guest = run(*ssh,
                "printf 'arch='; uname -m; "
                "printf 'sudo='; if sudo -n true </dev/null 2>/dev/null; then echo yes; else echo no; fi; "
                "printf 'nmcli='; if command -v nmcli >/dev/null; then echo yes; else echo no; fi; "
                "printf 'ipv4='; if command -v ip >/dev/null; then echo yes; else echo no; fi")
    values = dict(line.split("=", 1) for line in guest.splitlines() if "=" in line)
    if values.get("arch") not in ("aarch64", "arm64"):
        raise ValueError("Unexpected guest architecture")
    if any(values.get(k) != "yes" for k in ("nmcli", "ipv4")):
        raise ValueError(f"Guest network tooling is not ready: {values}")
    if values.get("sudo") not in ("yes", "no"):
        raise ValueError("Guest administrative capability not reported")
    # Administrative privilege is optional for preflight: guest network
    # configuration belongs in immutable CoreOS provisioning, not SSH.
    return values


def qualify():
    plan_raw = PLAN.read_bytes()
    plan = json.loads(plan_raw)
    candidate = plan["networkCandidate"]
    if set(plan["placements"]) != {"farcaster", "world1"}:
        raise ValueError("Exactly one Farcaster and one World required")
    if candidate["transport"] != "qemu-socket-over-private-podman-network":
        raise ValueError("Unsupported transport proposal")
    if candidate["egress"] != "deny-by-default" or not candidate["podmanInternal"]:
        raise ValueError("Fail-closed transport constraints missing")
    if candidate["farcasterIPv4"] == candidate["world1IPv4"]:
        raise ValueError("Guest transit addresses must differ")
    revisions = os.environ.get("NIX_XD_SELECTED_PROJECT_REV", "")
    if not binding.SHA.fullmatch(revisions):
        raise ValueError("Exact project revision required")
    if binding.run("git", "-C", str(ROOT.parents[1]), "rev-parse", "HEAD") != revisions:
        raise ValueError("Selected checkout revision changed")
    bound = binding.bind("world1")
    machine = bound["machine"]
    state = Path(bound["stateRoot"])
    key = Path(os.environ.get("SHOAL_SSH_KEY", str(Path.home() / ".ssh/starwisp-test"))).expanduser()
    if not key.is_file():
        raise ValueError("Missing guest SSH client key")
    observations = {}
    for name in ("farcaster", "world1"):
        placement = plan["placements"][name]
        receipt = bound["bindings"][name]
        observed = inspect_runner(machine, placement, receipt["containerId"])
        observed["guest"] = guest_preflight(placement, state / placement["instance"] / "known_hosts", key)
        observations[name] = observed
        print(f"AGNI_SHOAL_NETWORK_GUEST=preflight-passed placement={name} sudo={observed['guest']['sudo']}", flush=True)
    receipt = {"schemaVersion": 1, "stage": "network-preflight",
               "agniRevision": revisions, "planSha256": hashlib.sha256(plan_raw).hexdigest(),
               "binding": bound["bindings"], "observations": observations,
               "candidate": candidate,
               "qualification": {"network": "not-assessed", "egress": "not-assessed",
                                 "services": "not-assessed"}}
    root = Path(os.environ.get("SHOAL_RECEIPT_ROOT",
                str(Path.home() / ".local/state/agni/shoal/receipts"))).expanduser()
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    payload = json.dumps(receipt, sort_keys=True, indent=2) + "\n"
    digest = hashlib.sha256(payload.encode()).hexdigest()
    path = root / f"network-preflight-{digest}.json"
    if path.exists():
        if path.read_text() != payload:
            raise ValueError("Preflight receipt collision")
    else:
        temporary = root / f".network-preflight-{os.getpid()}"
        with temporary.open("x") as handle:
            os.fchmod(handle.fileno(), 0o600)
            handle.write(payload)
        try:
            os.link(temporary, path)
        except FileExistsError:
            if path.read_text() != payload:
                raise ValueError("Concurrent receipt differs")
        finally:
            temporary.unlink(missing_ok=True)
    print(f"AGNI_SHOAL_NETWORK_PREFLIGHT=passed receipt={path}", flush=True)
    print("AGNI_SHOAL_NETWORK=not-assessed", flush=True)
    print("AGNI_SHOAL_EGRESS=not-assessed", flush=True)


if __name__ == "__main__":
    try:
        qualify()
    except (ValueError, OSError, KeyError, subprocess.SubprocessError,
            json.JSONDecodeError, subprocess.TimeoutExpired) as exc:
        print("AGNI_SHOAL_NETWORK_PREFLIGHT=blocked reason=" + str(exc), file=sys.stderr)
        sys.exit(1)
