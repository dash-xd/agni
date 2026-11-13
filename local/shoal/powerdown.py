#!/usr/bin/env python3
"""Request graceful ACPI poweroff only from a pinned QMP-enabled Shoal guest."""
import json
import os
from pathlib import Path
import socket
import subprocess
import sys
import time

import binding
import migration

ROOT = Path(__file__).resolve().parent
QMP_PORTS = {"farcaster": 42222, "world1": 42223}


def inspect(machine, placement, root, stage):
    state = root / placement["instance"]
    manifest = migration.manifest(state / "manifest.txt")
    port = QMP_PORTS[stage]
    if manifest.get("qmp_host_port") != str(port):
        raise ValueError("QMP not enrolled on original managed launch; no shutdown attempted")
    details = json.loads(binding.run(
        "podman", "--connection", machine, "inspect", placement["container"]))
    if len(details) != 1:
        raise ValueError("Expected one managed guest container")
    item = details[0]
    if not item.get("State", {}).get("Running") or manifest.get("container_id") != item.get("Id"):
        raise ValueError("Running managed container ID mismatch")
    published = item.get("NetworkSettings", {}).get("Ports", {}).get("4444/tcp", [])
    if not any(p.get("HostIp") == "127.0.0.1" and p.get("HostPort") == str(port)
               for p in (published or [])):
        raise ValueError("QMP endpoint is not loopback-bound to the expected port")
    return item["Id"], port


def receive(connection):
    data = bytearray()
    while len(data) < 65536:
        chunk = connection.recv(4096)
        if not chunk:
            raise ValueError("QMP channel closed")
        data.extend(chunk)
        if b"\n" in data:
            record, remaining = data.split(b"\n", 1)
            # Events can interleave with command replies; caller relies on
            # a single socket and reads messages without concurrency.
            return json.loads(record), remaining
    raise ValueError("QMP reply exceeds limit")


def read_line(sock, pending):
    while b"\n" not in pending:
        chunk = sock.recv(4096)
        if not chunk:
            raise ValueError("QMP channel closed")
        pending += chunk
        if len(pending) > 65536:
            raise ValueError("QMP reply exceeds limit")
    row, pending = pending.split(b"\n", 1)
    return json.loads(row), pending


def command(sock, pending, execute):
    sock.sendall((json.dumps({"execute": execute}) + "\n").encode())
    for _ in range(20):
        response, pending = read_line(sock, pending)
        if "event" in response:
            continue
        if "error" in response:
            raise ValueError("QMP rejected " + execute + ": " + json.dumps(response["error"]))
        if "return" not in response:
            raise ValueError("Unexpected QMP reply")
        return pending
    raise ValueError("Too many unsolicited QMP events")


def powerdown(machine, placement, root, stage):
    cid, port = inspect(machine, placement, root, stage)
    with socket.create_connection(("127.0.0.1", port), timeout=10) as sock:
        sock.settimeout(10)
        greeting, pending = read_line(sock, b"")
        if "QMP" not in greeting:
            raise ValueError("Unexpected QMP greeting")
        pending = command(sock, pending, "qmp_capabilities")
        command(sock, pending, "system_powerdown")
    print("AGNI_SHOAL_POWERDOWN=requested placement=" + stage + " container=" + cid, flush=True)
    # A QMP success response proves only that ACPI poweroff was requested.
    # Verify the same container exited normally; backup capture independently
    # validates shutdown evidence and backing image identity.
    deadline = time.monotonic() + 240
    while time.monotonic() < deadline:
        item = json.loads(binding.run(
            "podman", "--connection", machine, "inspect", placement["container"]))[0]
        if item.get("Id") != cid:
            raise ValueError("Managed container changed during powerdown")
        status = item.get("State", {})
        if status.get("Status") == "exited":
            if status.get("ExitCode") != 0 or status.get("OOMKilled"):
                raise ValueError("QEMU exited abnormally")
            print("AGNI_SHOAL_POWERDOWN=exited placement=" + stage + " container=" + cid, flush=True)
            return
        time.sleep(2)
    raise ValueError("Guest failed to exit after QMP poweroff; no forced stop attempted")


def main():
    revision = os.environ.get("NIX_XD_SELECTED_PROJECT_REV", "")
    if not binding.SHA.fullmatch(revision):
        raise ValueError("Exact selected Agni source revision required")
    if binding.run("git", "-C", str(ROOT.parents[1]), "rev-parse", "HEAD") != revision:
        raise ValueError("Selected source revision changed")
    stage = os.environ.get("SHOAL_POWERDOWN_STAGE", "")
    if stage not in QMP_PORTS:
        raise ValueError("Explicit SHOAL_POWERDOWN_STAGE=farcaster|world1 required")
    if os.environ.get("SHOAL_CONFIRM_POWERDOWN", "") != stage:
        raise ValueError("Explicit SHOAL_CONFIRM_POWERDOWN must match the selected stage")
    plan = json.loads((ROOT / "plan.json").read_text())
    placement = plan["placements"][stage]
    machine = os.environ.get("SHOAL_MACHINE", "coreos-arm64")
    if not machine.replace("-", "").replace("_", "").isalnum():
        raise ValueError("Invalid machine")
    state = Path(os.environ.get("SHOAL_STATE_ROOT",
        str(Path.home() / ".local/state/nix-xd/coreos"))).expanduser().resolve()
    powerdown(machine, placement, state, stage)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.SubprocessError,
            socket.timeout, json.JSONDecodeError) as exc:
        print("AGNI_SHOAL_POWERDOWN=blocked reason=" + str(exc), file=sys.stderr)
        sys.exit(1)
