#!/usr/bin/env python3
"""Prepare a read-only inventory and an unapplied Shoal network candidate."""
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import subprocess
import sys
import binding
import network

ROOT = Path(__file__).resolve().parent
MAC = {"farcaster": "02:53:48:4f:41:01", "world1": "02:53:48:4f:41:02"}


def regular(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError("Missing regular managed state: " + str(path))
    return path


def manifest(path):
    pairs = [s.split("=", 1) for s in regular(path).read_text().splitlines()]
    if any(len(p) != 2 for p in pairs) or len(set(p[0] for p in pairs)) != len(pairs):
        raise ValueError("Malformed or duplicate managed manifest fields")
    return dict(pairs)


def keyfile(name, address, subnet):
    net = ipaddress.ip_network(subnet, strict=True)
    ip = ipaddress.ip_address(address)
    if net.version != 4 or net.prefixlen != 30 or ip not in net.hosts():
        raise ValueError("Expected distinct /30 transit hosts")
    return (f"[connection]\nid=agni-shoal-{name}\ntype=ethernet\nautoconnect=true\n\n"
            f"[ethernet]\nmac-address={MAC[name]}\n\n"
            f"[ipv4]\nmethod=manual\naddress1={ip}/{net.prefixlen}\n"
            "never-default=true\nignore-auto-routes=true\nignore-auto-dns=true\n\n"
            "[ipv6]\nmethod=disabled\n")


def ssh_observe(placement, known, key, command):
    args = ["ssh", "-T", "-i", str(key), "-p", str(placement["sshPort"]),
            "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes",
            "-o", "StrictHostKeyChecking=yes",
            "-o", "UserKnownHostsFile=" + str(known),
            "-o", "ConnectTimeout=8",
            placement["sshUser"] + "@" + placement["sshHost"], command]
    return json.loads(network.run(*args))


def write_once(path, content):
    if path.exists():
        if path.is_symlink() or path.read_text() != content:
            raise ValueError("Conflicting staged candidate: " + str(path))
        return
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as out:
        out.write(content)


def prepare():
    raw = (ROOT / "plan.json").read_bytes()
    plan = json.loads(raw)
    candidate = plan["networkCandidate"]
    if set(plan["placements"]) != set(MAC) or plan["schemaVersion"] != 1:
        raise ValueError("Unexpected one-Farcaster one-World plan")
    if (candidate["transport"] != "qemu-socket-over-private-podman-network"
            or candidate["applied"] is not False or not candidate["podmanInternal"]
            or candidate["egress"] != "deny-by-default"
            or not candidate["requiresControlledRecreation"]):
        raise ValueError("Unsupported or already-applied network candidate")
    if candidate["farcasterIPv4"] == candidate["world1IPv4"]:
        raise ValueError("Same transit IP selected for both guests")
    revision = os.environ.get("NIX_XD_SELECTED_PROJECT_REV", "")
    if not binding.SHA.fullmatch(revision):
        raise ValueError("Exact Agni revision required")
    if binding.run("git", "-C", str(ROOT.parents[1]), "rev-parse", "HEAD") != revision:
        raise ValueError("Selected Agni revision changed")
    profiles = {name: keyfile(name, candidate[name + "IPv4"], candidate["transitCIDR"])
                for name in MAC}
    bound = binding.bind("world1")
    state = Path(bound["stateRoot"])
    key = regular(Path(os.environ.get("SHOAL_SSH_KEY",
                  str(Path.home() / ".ssh/starwisp-test"))).expanduser())
    observations = {}
    for name in ("farcaster", "world1"):
        placement = plan["placements"][name]
        receipt = bound["bindings"][name]
        guest_state = state / placement["instance"]
        overlay = regular(guest_state / "overlay.qcow2")
        known = regular(guest_state / "known_hosts")
        regular(guest_state / "build.txt")
        saved = manifest(guest_state / "manifest.txt")
        if (saved.get("container_id") != receipt["containerId"]
                or saved.get("port") != str(placement["sshPort"])
                or not saved.get("runner", "").startswith("sha256:")):
            raise ValueError(name + ": managed QEMU manifest differs from running identity")
        runner = network.inspect_runner(bound["machine"], placement, receipt["containerId"])
        runner["guestTools"] = network.guest_preflight(placement, known, key)
        runner["bootId"] = receipt["bootId"]
        runner["overlay"] = {"path": str(overlay), "sizeBytes": overlay.stat().st_size,
                             "live": True, "consistentBackup": False}
        runner["ipv4Addresses"] = ssh_observe(placement, known, key, "ip -j -4 addr show")
        runner["ipv4Routes"] = ssh_observe(placement, known, key, "ip -j -4 route show")
        observations[name] = runner
        print("AGNI_SHOAL_MIGRATION_GUEST=inventory-passed placement=" + name, flush=True)

    qemu = {
        "managementCandidate": "user,id=n0,restrict=on,hostfwd=tcp::2222-:22",
        "farcasterTransit": "socket,id=shoal,listen=0.0.0.0:" + str(candidate["qemuSocketPort"]),
        "worldTransit": "socket,id=shoal,connect=" +
                        plan["placements"]["farcaster"]["container"] + ":" +
                        str(candidate["qemuSocketPort"]),
        "macAddresses": MAC,
        "podmanInternalNetwork": candidate["podmanNetwork"],
        "applied": False,
    }
    inventory = {
        "schemaVersion": 1, "agniRevision": revision, "stage": "network-migration-prepare",
        "planSha256": hashlib.sha256(raw).hexdigest(),
        "bindings": bound["bindings"], "observations": observations,
        "candidate": candidate, "qemuCandidate": qemu,
        "activationBlockers": [
            "Scoped root-owned NetworkManager keyfile installer not yet qualified",
            "Consistent stopped-guest QCOW2 backups not yet captured",
            "QEMU private transport and management SSH survival not yet qualified",
            "IPv4 and IPv6 egress isolation and Squid routing not yet qualified"],
        "qualification": {"inventory": "passed", "migration": "not-activated",
                          "network": "not-assessed", "egress": "not-assessed",
                          "services": "not-assessed"},
    }
    content = json.dumps(inventory, sort_keys=True, indent=2) + "\n"
    digest = hashlib.sha256(content.encode()).hexdigest()
    directory = Path(os.environ.get(
        "SHOAL_MIGRATION_ROOT", str(Path.home() / ".local/state/agni/shoal/network-migration"))
    ).expanduser() / (revision + "-" + digest)
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    for name, payload in {
        "inventory.json": content, "farcaster.nmconnection": profiles["farcaster"],
        "world1.nmconnection": profiles["world1"],
        "qemu-candidate.json": json.dumps(qemu, sort_keys=True, indent=2) + "\n",
    }.items():
        write_once(directory / name, payload)
    print("AGNI_SHOAL_MIGRATION_PREPARE=passed directory=" + str(directory), flush=True)
    print("AGNI_SHOAL_MIGRATION_ACTIVATE=blocked pending=scoped-guest-config-and-stopped-disk-backups", flush=True)
    print("AGNI_SHOAL_NETWORK=not-assessed", flush=True)
    print("AGNI_SHOAL_EGRESS=not-assessed", flush=True)


if __name__ == "__main__":
    try:
        prepare()
    except (ValueError, OSError, KeyError, TypeError, json.JSONDecodeError,
            subprocess.SubprocessError, subprocess.TimeoutExpired) as exc:
        print("AGNI_SHOAL_MIGRATION_PREPARE=blocked reason=" + str(exc), file=sys.stderr)
        sys.exit(1)
