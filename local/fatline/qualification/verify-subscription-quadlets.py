#!/usr/bin/env python3
"""Validate the complete inert subscription Quadlet artifact structurally."""
import argparse
import json
from pathlib import Path

SCOPE = "fatline-arm-vm1"
REVISION = "1788ee94235b83f2b6229b95acbc98469f3eaf85"
GUARD = "/run/agni/unqualified-subscription-activation"
EXPECTED = {
    "schema": 1,
    "scope": SCOPE,
    "subscription_revision": REVISION,
    "groups": ["a", "b"],
    "units": 4,
    "activation": "blocked",
    "worker": "disabled",
    "execution_factory": "not-yet-integrated",
}


def fields(path):
    result = {}
    for line in path.read_text().splitlines():
        if not line or line.startswith("["):
            continue
        key, sep, value = line.partition("=")
        if not sep:
            raise ValueError(f"malformed unit field in {path.name}")
        result.setdefault(key, []).append(value)
    return result


def one(values, key):
    entries = values.get(key, [])
    if len(entries) != 1:
        raise ValueError(f"{key} must occur exactly once")
    return entries[0]


def verify(directory):
    directory = Path(directory)
    if json.loads((directory / "manifest.json").read_text()) != EXPECTED:
        raise ValueError("manifest identity or activation contract mismatch")
    names = {
        f"{SCOPE}-subscription-{group}-{role}.container"
        for group in ("a", "b") for role in ("skymill", "processor")
    }
    actual = {p.name for p in directory.iterdir() if p.is_file()}
    network_name = SCOPE + ".network"
    if actual != names | {"manifest.json", network_name}:
        raise ValueError("unexpected, missing or additional Quadlet source files")
    network = (directory / network_name).read_text()
    if network != "[Network]\nNetworkName=nix-xd-" + SCOPE + "\nInternal=true\n":
        raise ValueError("incorrect or missing shared network Quadlet")
    for group in ("a", "b"):
        prefix = f"{SCOPE}-subscription-{group}"
        skymill = directory / f"{prefix}-skymill.container"
        processor = directory / f"{prefix}-processor.container"
        for path in (skymill, processor):
            content = path.read_text()
            if "[Install]" in content or "[Container]" not in content or "[Service]" not in content:
                raise ValueError(f"unsafe or incomplete Quadlet: {path.name}")
            values = fields(path)
            if one(values, "Network") != network_name:
                raise ValueError("unresolved network dependency")
            if one(values, "ConditionPathExists") != GUARD:
                raise ValueError("missing inert guard")
            for key, expected in (
                ("ReadOnly", "true"), ("NoNewPrivileges", "true"),
                ("DropCapability", "all"), ("Restart", "on-failure"),
            ):
                if one(values, key) != expected:
                    raise ValueError(f"unsafe {key} for {path.name}")
            if any(line.startswith(("Environment=REDIS_PASSWORD=", "Environment=SKYMILL_TOKEN="))
                   for line in content.splitlines()):
                raise ValueError("inline credential detected")
        a = fields(skymill)
        b = fields(processor)
        other = "b" if group == "a" else "a"
        if f"{SCOPE}-redis.service" not in one(a, "Requires").split():
            raise ValueError("Skymill must depend on Redis")
        if f"{prefix}-skymill.service" not in one(b, "Requires").split():
            raise ValueError("processor must depend on its Skymill service")
        if one(b, "BindsTo") != f"{prefix}-skymill.service":
            raise ValueError("processor must bind to its own Skymill service")
        all_environments_b = b.get("Environment", [])
        all_environments_a = a.get("Environment", [])
        expected_group = "agni-worker-candidate" if group == "a" else "agni-worker-candidate-subscription-b"
        for envs in (all_environments_a, all_environments_b):
            if envs.count("SKYMILL_CONSUMER_GROUP=" + expected_group) != 1:
                raise ValueError("consumer group mismatch")
        if all_environments_b.count("PROBOT_RUNTIME_WORKER_ENABLED=false") != 1:
            raise ValueError("worker must remain disabled")
        for role, values in (("skymill", a), ("probot", b)):
            mount = f"/credentials/{group}/{role}:/run/credentials:ro"
            if sum(mount in v for v in values.get("Volume", [])) != 1:
                raise ValueError("credential boundary mismatch")
            if any(f"/credentials/{other}/" in v for v in values.get("Volume", [])):
                raise ValueError("cross-subscription credential sharing")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("directory")
    args = p.parse_args()
    verify(Path(args.directory))
    print("AGNI_DECLARATIVE_PROCESSORS_ARTIFACT=passed units=4 manifest=validated worker=disabled")


if __name__ == "__main__":
    main()
