#!/usr/bin/env python3
"""Render a credential-free Redis ACL policy for pinned VM1 webhook roles."""
import argparse
import copy
import hashlib
import json
from pathlib import Path

ROLES = {"logma", "skymill", "bootstrap", "probot_state",
         "lifecycle_publish", "lifecycle_subscribe"}

def build_policy(baseline, manifest, scope):
    if baseline.get("schema") != 1 or manifest.get("schema") != 1:
        raise ValueError("Unsupported ACL/source manifest")
    if manifest.get("scenario") != "probot-webhook":
        raise ValueError("Expected pinned webhook scenario")
    sources = manifest["sources"]
    if set(sources) != {"logma", "skymill", "probot-runtime"}:
        raise ValueError("Incomplete source manifest")
    policy = copy.deepcopy(baseline)
    policy["scope"] = scope
    policy["skymillStream"] = f"{scope}:skymill:stream:github.webhooks"
    policy["componentRevisions"]["logma"] = sources["logma"]["revision"]
    policy["componentRevisions"]["skymill"] = sources["skymill"]["revision"]
    tag = hashlib.sha256(b"xd-dash\x00probot-runtime\x00github-webhooks\x00github.webhooks").hexdigest()[:32]
    bound = "skymill:{" + tag + "}:"
    users = policy["users"]
    users["skymill"]["keys"] = [bound + "*"]
    users["skymill"]["commands"] = sorted(set(users["skymill"]["commands"]) |
        {"xlen", "hgetall", "hset", "hget", "exists", "pexpire", "xinfo", "xpending", "xclaim"})
    prefix = f"{scope}:fatline:runtime:probot-runtime:probot-test"
    users["probot_state"] = {
        "keys": [prefix + ":*", "xd-dash:fatline:auth:binding-artifact:*"],
        "channels": [],
        "commands": ["ping", "hello", "client", "select", "get", "set",
                     "hget", "hgetall", "hset", "hsetnx", "hdel", "del",
                     "exists", "zadd", "zrange", "eval", "publish"],
    }
    users["lifecycle_publish"] = {
        "keys": [], "channels": [f"{scope}:logma:lifecycle:probot-runtime:*"],
        "commands": ["ping", "hello", "client", "publish"],
    }
    users["lifecycle_subscribe"] = {
        "keys": [], "channels": [f"{scope}:logma:lifecycle:probot-runtime:*"],
        "commands": ["ping", "hello", "client", "subscribe", "unsubscribe", "psubscribe", "punsubscribe"],
    }
    if set(users) != ROLES:
        raise ValueError("Unexpected Redis ACL identities")
    if any("~*" in str(user) or "+@all" in str(user) for user in users.values()):
        raise ValueError("Unbounded Redis grant")
    return policy

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--sources", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--scope", default="fatline-arm-vm1")
    args = parser.parse_args()
    policy = build_policy(json.loads(args.baseline.read_text()),
                          json.loads(args.sources.read_text()), args.scope)
    payload = json.dumps(policy, sort_keys=True, indent=2) + "\n"
    if args.output.exists() and args.output.read_text() != payload:
        raise SystemExit("Refusing to replace different Redis ACL policy")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(payload)
    print("AGNI_PROBOT_REDIS_POLICY=passed principals=6 secrets=excluded")
    print("AGNI_PROBOT_REDIS_ACTIVATION=blocked reason=runtime-credential-and-command-qualification")
if __name__ == "__main__":
    main()
