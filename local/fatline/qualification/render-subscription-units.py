#!/usr/bin/env python3
"""Render inert, two-subscription Quadlet candidates; never install or activate."""
import argparse
import json
from pathlib import Path
import re

IDENTITY = re.compile(r"[a-z][a-z0-9-]{0,39}")
STORE_BINARY = re.compile(r"/nix/store/[a-z0-9]{32}-[A-Za-z0-9._+-]+(?:/[A-Za-z0-9_./+-]+)?")
STORE_PROBOT = re.compile(r"/nix/store/[a-z0-9]{32}-probot")
REVISION = "1788ee94235b83f2b6229b95acbc98469f3eaf85"
SCOPE = "fatline-arm-vm1"
GROUPS = ("a", "b")


def render(spec, output):
    if spec.get("schema") != 1 or spec.get("scope") != SCOPE or spec.get("subscription_revision") != REVISION:
        raise ValueError("unqualified subscription composition identity")
    for name in ("skymill_binary", "node_binary"):
        if not STORE_BINARY.fullmatch(spec.get(name, "")):
            raise ValueError("invalid immutable executable: " + name)
    if not STORE_PROBOT.fullmatch(spec.get("probot_root", "")):
        raise ValueError("invalid immutable Probot source")
    if not isinstance(spec.get("runtime_root"), str) or not re.fullmatch(
        r"/[a-zA-Z0-9/_.+-]+", spec["runtime_root"]
    ) or ".." in Path(spec["runtime_root"]).parts:
        raise ValueError("invalid runtime root")
    root = spec["runtime_root"]
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    if list(output.iterdir()):
        raise ValueError("output must be empty")
    for group in GROUPS:
        prefix = SCOPE + "-subscription-" + group
        group_id = "agni-worker-candidate" if group == "a" else "agni-worker-candidate-subscription-b"
        skymill_name = prefix + "-skymill"
        processor_name = prefix + "-processor"
        credential_root = root + "/credentials/" + group
        # Both service definitions are deliberately inert: no [Install] section,
        # no activation-authorizing path, and no worker-enabled Probot execution.
        skymill = [
            "[Unit]",
            "Description=Inert Agni Skymill " + group + " composition candidate",
            "ConditionPathExists=/run/agni/unqualified-subscription-activation",
            "Requires=" + SCOPE + "-redis.service " + SCOPE + "-nginx.service",
            "After=" + SCOPE + "-redis.service " + SCOPE + "-nginx.service",
            "BindsTo=" + SCOPE + "-redis.service",
            "[Container]",
            "ContainerName=" + skymill_name,
            "Rootfs=" + root + "/rootfs",
            "User=1000:1000",
            "UserNS=keep-id:uid=1000,gid=1000",
            "Network=" + SCOPE + ".network",
            "NetworkAlias=skymill-" + group,
            "ReadOnly=true",
            "NoNewPrivileges=true",
            "DropCapability=all",
            "Volume=/var/mnt/nixstore:/nix/store:ro",
            "Volume=" + credential_root + "/skymill:/run/credentials:ro",
            "Environment=SKYMILL_CONSUMER_GROUP=" + group_id,
            "Environment=SKYMILL_CONSUMER=subscription-" + group,
            "Environment=SKYMILL_STREAM=worker-candidate.webhooks",
            "Environment=SKYMILL_HTTP_TOKEN_FILE=/run/credentials/http-token",
            "Exec=" + spec["skymill_binary"],
            "[Service]",
            "Restart=on-failure",
            "RestartSec=5",
            "TimeoutStartSec=90",
        ]
        processor = [
            "[Unit]",
            "Description=Inert Agni Probot processor " + group + " composition candidate",
            "ConditionPathExists=/run/agni/unqualified-subscription-activation",
            "Requires=" + skymill_name + ".service " + SCOPE + "-redis.service",
            "After=" + skymill_name + ".service " + SCOPE + "-redis.service",
            "BindsTo=" + skymill_name + ".service",
            "Wants=" + SCOPE + "-logma.service",
            "After=" + SCOPE + "-logma.service",
            "[Container]",
            "ContainerName=" + processor_name,
            "Rootfs=" + root + "/rootfs",
            "User=1000:1000",
            "UserNS=keep-id:uid=1000,gid=1000",
            "Network=" + SCOPE + ".network",
            "NetworkAlias=processor-" + group,
            "ReadOnly=true",
            "NoNewPrivileges=true",
            "DropCapability=all",
            "Volume=/var/mnt/nixstore:/nix/store:ro",
            "Volume=" + credential_root + "/probot:/run/credentials:ro",
            "Environment=SKYMILL_URL=http://skymill-" + group + ":8081",
            "Environment=SKYMILL_CONSUMER_GROUP=" + group_id,
            "Environment=PROBOT_RUNTIME_WORKER_ENABLED=false",
            # Subscription-aware factory wiring is NOT qualified for regular router startup.
            "Exec=" + spec["node_binary"] + " " + spec["probot_root"] + "/router/serve.js",
            "[Service]",
            "Restart=on-failure",
            "RestartSec=5",
            "TimeoutStartSec=90",
        ]
        (output / (skymill_name + ".container")).write_text("\n".join(skymill) + "\n")
        (output / (processor_name + ".container")).write_text("\n".join(processor) + "\n")
    (output / "manifest.json").write_text(json.dumps({
        "schema": 1, "scope": SCOPE, "subscription_revision": REVISION,
        "groups": list(GROUPS), "units": 4,
        "activation": "blocked", "worker": "disabled",
        "execution_factory": "not-yet-integrated",
    }, sort_keys=True) + "\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("spec")
    parser.add_argument("output")
    args = parser.parse_args()
    render(json.loads(Path(args.spec).read_text()), Path(args.output))


if __name__ == "__main__":
    main()
