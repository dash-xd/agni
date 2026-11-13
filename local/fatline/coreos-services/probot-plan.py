#!/usr/bin/env python3
"""Render a non-secret, fail-closed CoreOS VM1 Probot composition candidate."""
import argparse
import hashlib
import json
import os
from pathlib import Path
from importlib.util import module_from_spec, spec_from_file_location

spec = spec_from_file_location("agni_candidate_output", Path(__file__).with_name("candidate-output.py"))
candidate_output = module_from_spec(spec)
spec.loader.exec_module(candidate_output)
import re

STORE = re.compile(r"/nix/store/[a-z0-9]{32}-[A-Za-z0-9._+-]+")
REV = re.compile(r"[a-f0-9]{40}")
ROLES = ("skymill", "logma", "probot-runtime")
NAMES = {"skymill": "skymill-http", "logma": "logma-lifecycle", "probot-runtime": "probot"}


def validate(artifact, source):
    if artifact.get("schema") != 1 or artifact.get("system") != "aarch64-linux":
        raise ValueError("Unsupported ARM64 artifact manifest")
    if artifact.get("ghxd_credentials_included") is not False:
        raise ValueError("GHXD credentials must never be part of an application artifact")
    if source.get("schema") != 1 or source.get("scenario") != "probot-webhook":
        raise ValueError("Unsupported webhook source contract")
    entries = artifact.get("artifacts", {})
    if set(entries) != set(ROLES) or set(source.get("sources", {})) != set(ROLES):
        raise ValueError("Missing or unknown application components")
    for role in ROLES:
        item = entries[role]
        expected = source["sources"][role]["revision"]
        path = item.get("store", "")
        if not REV.fullmatch(expected) or item.get("revision") != expected:
            raise ValueError("Artifact revision mismatch for " + role)
        if not STORE.fullmatch(path) or not path.endswith("-" + NAMES[role]):
            raise ValueError("Invalid Nix store artifact: " + role)
    for role in ROLES:
        location = Path(entries[role]["store"])
        if role == "probot-runtime":
            if not (location / "router" / "serve.js").is_file():
                raise ValueError("Probot router is absent from immutable Node artifact")
        elif not location.is_file() or not os.access(location, os.X_OK):
            raise ValueError("Native executable missing from owner store: " + role)
    node = artifact.get("node", "")
    if not Path(node).is_file() or not os.access(node, os.X_OK):
        raise ValueError("Node executable unavailable from owner store")
    if not re.fullmatch(STORE.pattern + r"/bin/node", node):
        raise ValueError("Node executable must be an exact Nix store path")
    return entries, node


def plan(artifact, sources, scope):
    if not re.fullmatch(r"[a-z][a-z0-9-]{1,31}", scope):
        raise ValueError("Invalid CoreOS service scope")
    entries, node = validate(artifact, sources)
    state = "/home/wisp/.local/state/nix-xd/fatline/" + scope
    app = state + "/services"
    units = {}
    roles = {
        "skymill": {
            "executable": entries["skymill"]["store"],
            "endpoint": "skymill:8081",
            "redis_principal": "skymill",
            "credentials": ("redis",),
            "dependencies": (scope + "-redis.service",),
        },
        "logma": {
            "executable": entries["logma"]["store"],
            "endpoint": "logma:18081",
            "redis_principal": "logma",
            "credentials": ("redis", "api-key"),
            "dependencies": (scope + "-redis.service",),
        },
        "probot": {
            "executable": node + " " + entries["probot-runtime"]["store"] + "/router/serve.js",
            "endpoint": "probot:3000",
            "redis_principal": "probot_state",
            "credentials": ("state", "publish", "operator", "github-app-key", "webhook-secret"),
            "dependencies": (scope + "-redis.service", scope + "-skymill.service", scope + "-logma.service"),
        },
    }
    # The v2 Skymill provider derives Redis keys from the immutable Binding,
    # not from Agni's older scope-prefixed stream convention.
    binding = ("xd-dash", "probot-runtime", "github-webhooks", "github.webhooks")
    tag = hashlib.sha256("\x00".join(binding).encode()).hexdigest()[:32]
    physical_stream = "skymill:{" + tag + "}:stream:github.webhooks"
    for role, cfg in roles.items():
        deps = " ".join(cfg["dependencies"])
        path = app + "/credentials/" + role
        units[scope + "-" + role + ".container"] = (
            "[Unit]\n"
            "Description=Agni Probot webhook " + scope + " " + role + "\n"
            "Requires=" + deps + "\n"
            "After=" + deps + "\n\n"
            "[Container]\n"
            "ContainerName=" + scope + "-" + role + "\n"
            "Rootfs=" + app + "/rootfs\n"
            "Network=" + scope + ".network\n"
            "NetworkAlias=" + role + "\n"
            "UserNS=keep-id:uid=1000,gid=1000\n"
            "User=1000:1000\n"
            "ReadOnly=true\n"
            "NoNewPrivileges=true\n"
            "DropCapability=all\n"
            "SecurityLabelDisable=true\n"
            "Volume=/var/mnt/nixstore:/nix/store:ro\n"
            "Volume=" + path + ":/run/credentials:ro\n"
            "Tmpfs=/tmp:rw,nosuid,nodev,size=4m\n"
            "Environment=FATLINE_SCOPE=" + scope + "\n"
            "Exec=" + cfg["executable"] + "\n\n"
            "[Service]\n"
            "Restart=on-failure\n"
            "TimeoutStartSec=180\n"
        )
    return {
        "schema": 1,
        "scope": scope,
        "system": "aarch64-linux",
        "unit_templates": units,
        "roles": roles,
        "source_revisions": {k: v["revision"] for k, v in sources["sources"].items()},
        "activation": "blocked-until-role-env-redis-acl-and-github-app-secrets-bound",
        "network": "private-no-published-http-ports",
        "rootfs": app + "/rootfs",
        "skymill_binding_stream_key": physical_stream,
        "old_scope_prefixed_acl_compatible": False,
        "store_mount": "/var/mnt/nixstore:/nix/store:ro",
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--artifacts", type=Path, required=True)
    parser.add_argument("--sources", type=Path, required=True)
    parser.add_argument("--scope", default="fatline-arm-vm1")
    output = parser.add_mutually_exclusive_group(required=True)
    output.add_argument("--output", type=Path)
    output.add_argument("--output-dir", type=Path)
    args = parser.parse_args()
    candidate = plan(json.loads(args.artifacts.read_text()),
                     json.loads(args.sources.read_text()), args.scope)
    if args.output_dir is not None:
        selected = candidate_output.retain_candidate(args.output_dir, candidate, "guest-plan")
    elif args.output.exists():
        prior = json.loads(args.output.read_text())
        if prior != candidate:
            raise SystemExit("Refusing to overwrite different guest composition")
        selected = args.output
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        tmp = args.output.with_suffix(args.output.suffix + ".tmp")
        tmp.write_text(json.dumps(candidate, sort_keys=True, indent=2) + "\\n")
        os.chmod(tmp, 0o600)
        os.replace(tmp, args.output)
        selected = args.output
    print("AGNI_PROBOT_GUEST_PLAN_PATH=" + str(selected))
    print("AGNI_PROBOT_GUEST_COMPOSITION=passed roles=3 scope=" + args.scope)
    print("AGNI_PROBOT_GUEST_ACTIVATION=blocked reason=runtime-authority-and-redis-acls-not-bound")


if __name__ == "__main__":
    main()
