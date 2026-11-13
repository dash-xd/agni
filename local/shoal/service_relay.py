#!/usr/bin/env python3
"""Prove a World->Farcaster application response via disposable SSH relay.

This is transport-only and does not qualify direct VM networking or egress.
"""
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import sys
import time
import urllib.parse

import binding

ROOT = Path(__file__).resolve().parent


def ssh_args(item, key, known):
    return ["ssh", "-T", "-i", str(key), "-p", str(item["sshPort"]),
            "-o", "BatchMode=yes", "-o", "IdentitiesOnly=yes",
            "-o", "StrictHostKeyChecking=yes",
            "-o", "UserKnownHostsFile=" + str(known),
            "-o", "ConnectTimeout=8",
            item["sshUser"] + "@" + item["sshHost"]]


def endpoint():
    port_raw = os.environ.get("SHOAL_FARCASTER_SERVICE_PORT", "80")
    if not re.fullmatch(r"[0-9]{1,5}", port_raw) or not 1 <= int(port_raw) <= 65535:
        raise ValueError("Invalid Farcaster service port")
    path = os.environ.get("SHOAL_SERVICE_PATH", "/healthz")
    parsed = urllib.parse.urlsplit(path)
    if (not path.startswith("/") or path.startswith("//") or
            parsed.scheme or parsed.netloc or "\n" in path or "\r" in path or
            len(path) > 1024):
        raise ValueError("Service path must be an absolute HTTP path")
    return int(port_raw), path


def wait_bound(port, process):
    for _ in range(30):
        if process.poll() is not None:
            raise ValueError("SSH relay exited before becoming ready")
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return
        except OSError:
            time.sleep(0.1)
    raise ValueError("Farcaster relay did not bind")


def stop(process):
    if process is None:
        return
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=4)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=4)


def probe(farcaster, world, key, known_farcaster, known_world, port, path):
    # Local loopback relay is intentionally ephemeral; it is not VM routing.
    with socket.socket() as reservation:
        reservation.bind(("127.0.0.1", 0))
        relay_port = reservation.getsockname()[1]
    first = None
    second = None
    try:
        first = subprocess.Popen(
            ssh_args(farcaster, key, known_farcaster)[: -1] +
            ["-o", "ExitOnForwardFailure=yes", "-N",
             "-L", f"127.0.0.1:{relay_port}:127.0.0.1:{port}",
             ssh_args(farcaster, key, known_farcaster)[-1]],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE)
        wait_bound(relay_port, first)
        # The remote port is guest-local, so only World itself can use it.
        second = subprocess.Popen(
            ssh_args(world, key, known_world)[: -1] +
            ["-o", "ExitOnForwardFailure=yes", "-N",
             "-R", f"127.0.0.1:18080:127.0.0.1:{relay_port}",
             ssh_args(world, key, known_world)[-1]],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE)
        time.sleep(0.4)
        if second.poll() is not None or first.poll() is not None:
            raise ValueError("World-to-Farcaster SSH relay could not start")
        # Request originates inside World; the response originates at the
        # selected Farcaster service, not an HTTP server on the Mac.
        command = ("curl --noproxy '*' --fail --silent --show-error "
                   "--max-time 10 --output /dev/null --write-out '%{http_code}' "
                   + "'http://127.0.0.1:18080" + path.replace("'", "'\\''") + "'")
        result = subprocess.run(ssh_args(world, key, known_world) + [command],
                                capture_output=True, text=True, timeout=25)
        if result.returncode or not re.fullmatch(r"2[0-9]{2}", result.stdout.strip()):
            raise ValueError("World application request failed; curl exit=" +
                             str(result.returncode) + " status=" + result.stdout.strip() +
                             " stderr=" + result.stderr[-300:])
        return result.stdout.strip()
    finally:
        stop(second)
        stop(first)


def main():
    revision = os.environ.get("NIX_XD_SELECTED_PROJECT_REV", "")
    if not binding.SHA.fullmatch(revision):
        raise ValueError("Exact selected Agni revision required")
    if binding.run("git", "-C", str(ROOT.parents[1]), "rev-parse", "HEAD") != revision:
        raise ValueError("Selected source revision changed")
    service_port, path = endpoint()
    receipt = binding.bind("world1")
    plan = json.loads((ROOT / "plan.json").read_text())
    root = Path(receipt["stateRoot"])
    key = Path(os.environ.get(
        "SHOAL_SSH_KEY", str(Path.home() / ".ssh/starwisp-test"))).expanduser().resolve()
    farcaster = plan["placements"]["farcaster"]
    world = plan["placements"]["world1"]
    status = probe(farcaster, world, key,
                   root / farcaster["instance"] / "known_hosts",
                   root / world["instance"] / "known_hosts", service_port, path)
    print("AGNI_SHOAL_SERVICE_RELAY=passed world=world1 farcaster_status=" + status, flush=True)
    print("AGNI_SHOAL_DIRECT_NETWORK=not-assessed", flush=True)
    print("AGNI_SHOAL_EGRESS=not-assessed", flush=True)
    print("AGNI_SHOAL_FATLINE=not-assessed", flush=True)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, TypeError, subprocess.SubprocessError,
            subprocess.TimeoutExpired, json.JSONDecodeError) as exc:
        print("AGNI_SHOAL_SERVICE_RELAY=blocked reason=" + str(exc), file=sys.stderr)
        sys.exit(1)
