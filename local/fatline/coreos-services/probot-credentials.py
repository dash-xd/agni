#!/usr/bin/env python3
"""Build a new private VM1 Redis ACL generation without changing existing credentials."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys

ORIGINAL_ROLES = ("logma", "skymill", "bootstrap")
NEW_ROLES = ("probot_state", "lifecycle_publish", "lifecycle_subscribe")
ALL = ORIGINAL_ROLES + NEW_ROLES

def generate(policy_path, prior_acl, prior_credentials, output, renderer):
    if output.exists():
        raise ValueError("Credential generation exists; select a new generation")
    policy = json.loads(policy_path.read_text())
    if policy.get("schema") != 1 or policy.get("scope") != "fatline-arm-vm1":
        raise ValueError("Invalid scoped Redis policy")
    if set(policy.get("users", {})) != set(ALL):
        raise ValueError("Unexpected Redis principals")
    old_lines = prior_acl.read_text().splitlines()
    found = {}
    for line in old_lines:
        parts = line.split()
        if len(parts) < 3 or parts[0] != "user" or parts[1] in found:
            raise ValueError("Malformed or duplicate existing ACL user")
        found[parts[1]] = line
    required = {"default", "publisher", "subscriber", *ORIGINAL_ROLES}
    if not required.issubset(found):
        raise ValueError("Existing host-link and application identities are incomplete")
    unexpected = set(found) - required
    if unexpected:
        raise ValueError("Unknown existing Redis ACL principals: " + ",".join(sorted(unexpected)))
    if found["default"] != "user default off":
        raise ValueError("Existing Redis default identity is not disabled")
    for role in ORIGINAL_ROLES:
        if not (prior_credentials / role / "redis").is_file():
            raise ValueError("Missing pre-existing " + role + " credential")
    output.mkdir(mode=0o700, parents=True)
    secret_root = output / "acl-input"
    secret_root.mkdir(mode=0o700)
    credentials = {}
    for role in ALL:
        value = (prior_credentials / role / "redis").read_text().strip() if role in ORIGINAL_ROLES else secrets.token_hex(32)
        if len(value) < 32 or any(c.isspace() for c in value):
            raise ValueError("Invalid credential format: " + role)
        credentials[role] = value
        file = secret_root / role
        file.write_text(value + "\n")
        file.chmod(0o600)
    try:
        subprocess.run([sys.executable, str(renderer), str(policy_path),
                        str(secret_root), str(output / "users.acl")],
                       check=True, stdout=subprocess.DEVNULL)
    finally:
        for entry in secret_root.iterdir(): entry.unlink()
        secret_root.rmdir()
    new_lines = (output / "users.acl").read_text().splitlines()
    if len(new_lines) != 1 + len(ALL) or new_lines[0] != "user default off":
        raise ValueError("Unexpected rendered ACL")
    preserved = [found[name] for name in ("publisher", "subscriber")]
    (output / "users.acl").write_text("\n".join(new_lines + preserved) + "\n")
    (output / "users.acl").chmod(0o600)
    skymill_http_token = secrets.token_hex(32)
    directories = {
        "logma": {"redis": credentials["logma"],
                  "api-key": (prior_credentials / "logma" / "api-key").read_text().strip()},
        "skymill": {"redis": credentials["skymill"], "http-token": skymill_http_token},
        "bootstrap": {"redis": credentials["bootstrap"]},
        "probot": {"state": credentials["probot_state"],
                   "publish": credentials["lifecycle_publish"],
                   "operator": secrets.token_hex(32), "skymill-token": skymill_http_token},
        "lifecycle_subscribe": {"redis": credentials["lifecycle_subscribe"]},
    }
    for role, files in directories.items():
        directory = output / "credentials" / role
        directory.mkdir(mode=0o700, parents=True)
        for filename, value in files.items():
            if len(value) < 32 or any(c.isspace() for c in value):
                raise ValueError("Invalid credential material: " + role)
            file = directory / filename
            file.write_text(value if (role, filename) in (("skymill", "http-token"), ("probot", "skymill-token")) else value + "\n")
            file.chmod(0o600)
    policy_bytes = policy_path.read_bytes()
    (output / "policy.json").write_bytes(policy_bytes)
    (output / "policy.json").chmod(0o600)
    digest = hashlib.sha256((output / "users.acl").read_bytes()).hexdigest()
    (output / "digest").write_text(digest + "\n")
    print("AGNI_PROBOT_CREDENTIAL_GENERATION=passed original=preserved new=3")
    print("AGNI_PROBOT_REDIS_RESTART=blocked reason=explicit-activation-required")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--policy", required=True, type=Path)
    parser.add_argument("--old-acl", required=True, type=Path)
    parser.add_argument("--old-credentials", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--renderer", required=True, type=Path)
    args = parser.parse_args()
    generate(args.policy, args.old_acl, args.old_credentials, args.out, args.renderer)

if __name__ == "__main__":
    main()
