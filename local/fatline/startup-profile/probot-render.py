#!/usr/bin/env python3
"""Extend the existing Agni rootless startup-profile renderer for pinned VM1 webhook roles."""
import importlib.util
import json
from pathlib import Path
import re

STORE = re.compile(r"/nix/store/[a-z0-9]{32}-[A-Za-z0-9._+-]+")
REVISIONS = {"skymill", "logma", "probot-runtime"}

def _replace(lines, old, new):
    matches = [i for i, line in enumerate(lines) if line.startswith(old)]
    if len(matches) != 1:
        raise ValueError("Unexpected existing startup profile field: " + old)
    lines[matches[0]] = new

def render(spec, artifacts, source, destination, original_renderer):
    if spec.get("scope") != "fatline-arm-vm1":
        raise ValueError("Only pinned VM1 scope is supported")
    if artifacts.get("schema") != 1 or artifacts.get("system") != "aarch64-linux" or artifacts.get("ghxd_credentials_included") is not False:
        raise ValueError("Invalid non-secret ARM64 artifact contract")
    if source.get("schema") != 1 or source.get("scenario") != "probot-webhook" or set(source.get("sources", {})) != REVISIONS:
        raise ValueError("Invalid pinned webhook source selection")
    entries = artifacts.get("artifacts", {})
    if set(entries) != REVISIONS:
        raise ValueError("Incomplete application artifact selection")
    for role, basename in (("skymill", "skymill-http"), ("logma", "logma-lifecycle"), ("probot-runtime", "probot")):
        item = entries[role]
        if item.get("revision") != source["sources"][role]["revision"] or not re.fullmatch(r"[a-f0-9]{40}", item["revision"]):
            raise ValueError("Artifact SHA mismatch for " + role)
        if not STORE.fullmatch(item["store"]) or not item["store"].endswith("-" + basename):
            raise ValueError("Invalid immutable artifact for " + role)
    node = artifacts.get("node", "")
    if not re.fullmatch(STORE.pattern + r"/bin/node", node):
        raise ValueError("Pinned Node runtime required")
    if not re.fullmatch(r"[a-f0-9]{64}", spec.get("aclDigest", "")):
        raise ValueError("Runtime ACL digest required")
    profile = dict(spec)
    profile["logma"] = entries["logma"]["store"]
    profile["skymill"] = entries["skymill"]["store"]
    profile["webhook"] = {"mode": "staged", "revision": {role: entries[role]["revision"] for role in sorted(entries)}}
    original_renderer(profile, destination)
    scope = profile["scope"]
    base = profile["home"] + "/.local/state/nix-xd/fatline/" + scope
    app = base + "/services"

    redis = destination / (scope + "-redis.container")
    redis_lines = redis.read_text().splitlines()
    _replace(redis_lines, "Upholds=", "Upholds=" + " ".join(scope + "-" + role + ".service" for role in ("nginx", "logma", "skymill", "probot")))
    redis.write_text("\n".join(redis_lines) + "\n")

    skymill = destination / (scope + "-skymill.container")
    lines = skymill.read_text().splitlines()
    lines = [line for line in lines if not line.startswith(("Environment=REDIS_URL=", "Environment=REDIS_PASSWORD_FILE=", "Environment=SKYMILL_LISTEN_ADDR=", "Environment=SKYMILL_SCOPED_PROVIDER="))]
    _replace(lines, "Environment=SKYMILL_STREAM=", "Environment=SKYMILL_STREAM=github.webhooks")
    _replace(lines, "Exec=", "Exec=/bin/sh -ec 'export REDIS_PASSWORD=\"$(/bin/busybox cat /run/credentials/redis)\"; exec " + entries["skymill"]["store"] + "'")
    index = next(i for i, item in enumerate(lines) if item.startswith("Exec="))
    lines[index:index] = [
        "Environment=REDIS_ADDR=redis-proxy:6379", "Environment=REDIS_DB=0",
        "Environment=SKYMILL_ADDR=0.0.0.0:8081", "Environment=SKYMILL_ORG=xd-dash",
        "Environment=SKYMILL_TENANT=probot-runtime", "Environment=SKYMILL_APPLICATION=github-webhooks",
        "Environment=SKYMILL_CONSUMER_GROUP=probot-runtime",
        "Environment=SKYMILL_TOKEN_FILE=/run/credentials/http-token",
    ]
    skymill.write_text("\n".join(lines) + "\n")

    logma = destination / (scope + "-logma.container")
    lines = logma.read_text().splitlines()
    _replace(lines, "Exec=", "Exec=/bin/sh -ec 'export REDISCLI_AUTH=\"$(/bin/busybox cat /run/credentials/redis)\"; export PUBSUB_RESOURCE_REDIS_PASSWORD=\"$(/bin/busybox cat /run/credentials/redis)\"; export API_KEY=\"$(/bin/busybox cat /run/credentials/api-key)\"; exec " + entries["logma"]["store"] + "'")
    logma.write_text("\n".join(lines) + "\n")

    unit = [
        "[Unit]", "Description=Fatline " + scope + " Probot webhook",
        "StartLimitIntervalSec=120", "StartLimitBurst=3",
        "Requires=" + " ".join(scope + "-" + role + ".service" for role in ("redis", "skymill", "logma")),
        "After=" + " ".join(scope + "-" + role + ".service" for role in ("redis", "skymill", "logma")),
        "BindsTo=" + scope + "-redis.service", "PartOf=" + scope + "-redis.service",
        "[Container]", "ContainerName=" + scope + "-probot",
        "Rootfs=" + app + "/rootfs", "User=1000:1000",
        "UserNS=keep-id:uid=1000,gid=1000", "ReadOnly=true", "NoNewPrivileges=true",
        "DropCapability=all", "PodmanArgs=--read-only-tmpfs=false --security-opt label=disable",
        "Volume=/var/mnt/nixstore:/nix/store:ro",
        "Network=" + scope + ".network", "NetworkAlias=probot",
        "Volume=" + app + "/credentials/probot:/run/credentials:ro",
        "Tmpfs=/tmp:rw,nosuid,nodev,mode=1777,size=4m",
        "Environment=FATLINE_SCOPE=" + scope, "Environment=HOST=0.0.0.0",
        "Environment=PORT=3000", "Environment=REDIS_URL=redis://redis-proxy:6379/0",
        "Environment=REDIS_DB=0", "Environment=REDIS_USERNAME=probot_state",
        "Environment=REDIS_PASSWORD_FILE=/run/credentials/state",
        "Environment=LOGMA_ENABLED=true", "Environment=LOGMA_REDIS_USERNAME=lifecycle_publish",
        "Environment=LOGMA_REDIS_PASSWORD_FILE=/run/credentials/publish",
        "Environment=REDIS_PREFIX=xd-dash:fatline:runtime:probot-runtime:probot-test",
        "Environment=PROBOT_RUNTIME_ORG_ID=xd-dash", "Environment=PROBOT_RUNTIME_TENANT_ID=probot-test",
        "Environment=PROBOT_RUNTIME_PUBLIC_URL=http://probot:3000",
        "Environment=PROBOT_RUNTIME_OPERATOR_TOKEN_FILE=/run/credentials/operator",
        "Environment=SKYMILL_URL=http://skymill:8081",
        "Environment=SKYMILL_STREAM=github.webhooks",
        "Environment=SKYMILL_CONSUMER_GROUP=probot-runtime",
        "Environment=PROBOT_RUNTIME_WORKER_ENABLED=false",
        "Exec=/bin/sh -ec 'export SKYMILL_TOKEN=\\\"$(/bin/busybox cat /run/credentials/skymill-token)\\\"; exec " + node + " " + entries["probot-runtime"]["store"] + "/router/serve.js'",
        "[Service]", "TimeoutStartSec=300", "Restart=on-failure", "RestartSec=5",
        "[Install]", "WantedBy=default.target",
    ]
    (destination / (scope + "-probot.container")).write_text("\n".join(unit) + "\n")
    (destination / "webhook-artifacts.json").write_text(json.dumps(artifacts, sort_keys=True, indent=2) + "\n")
    print("AGNI_PROBOT_PROFILE_RENDER=passed roles=3 network=private credentials=unbound activation=blocked")
