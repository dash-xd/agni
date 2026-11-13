#!/usr/bin/env python3
"""Read-only guest inventory and fail-closed startup-profile adoption assessment."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

SCOPE = "fatline-arm-vm1"
ROLES = ("redis", "nginx", "logma", "skymill", "probot")
BASE_ROLES = ("redis", "nginx", "logma", "skymill")
HOST_IDENTITIES = ("default", "publisher", "subscriber")


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def assess(base, units, active_roles, *, bundle=None):
    """Construct non-secret evidence; never read credential values into output."""
    acl = base / "credentials" / "users.acl"
    redis_conf = base / "config" / "redis.conf"
    apps = base / "services"
    if not acl.is_file() or not redis_conf.is_file():
        raise ValueError("Existing Redis ACL and configuration must be readable")
    identities = {}
    for line in acl.read_text().splitlines():
        fields = line.split()
        if len(fields) < 3 or fields[0] != "user":
            raise ValueError("Unexpected existing ACL syntax")
        name = fields[1]
        if name in identities:
            raise ValueError("Duplicate Redis ACL identity")
        identities[name] = hashlib.sha256(line.encode()).hexdigest()
    if not set(HOST_IDENTITIES) <= identities:
        raise ValueError("Missing existing host-link identities")
    if not re.search(r"(?m)^user default off$", acl.read_text()):
        raise ValueError("Default Redis user is not disabled")
    unit_rows = {}
    for role in ROLES:
        path = units / (SCOPE + "-" + role + ".container")
        if path.is_symlink():
            raise ValueError("Refusing symlinked Quadlet: " + role)
        if path.exists():
            if not path.is_file():
                raise ValueError("Unexpected Quadlet file type: " + role)
            data = path.read_text()
            if "[Container]" not in data:
                raise ValueError("Unrecognized Quadlet definition: " + role)
            entries = re.findall(r"/nix/store/[a-z0-9]{32}-[A-Za-z0-9._+-]+(?:/[A-Za-z0-9/_.+-]+)*", data)
            unit_rows[role] = {"sha256": digest(path), "store_references": sorted(set(entries)),
                               "active": role in active_roles}
        elif role in active_roles:
            raise ValueError("Active role has no Quadlet: " + role)
    if not {"redis", "nginx"} <= set(unit_rows):
        raise ValueError("Missing Redis/Nginx Quadlet prerequisites")
    present_profile = (apps / "profile" / "profile.env").exists()
    complete_profile = all((apps / item).is_file() for item in
                           ("profile/profile.env", "profile/manifest.json", "bootstrap-template.acl"))
    if present_profile and not complete_profile:
        raise ValueError("Partial consolidated startup profile present")
    base_credentials = {role: (apps / "credentials" / role / "redis").is_file()
                        for role in ("logma", "skymill", "bootstrap")}
    missing = [role for role in BASE_ROLES if role not in unit_rows]
    if missing:
        state = "incomplete-runtime"
    elif complete_profile and all(base_credentials.values()):
        state = "consolidated-profile-present"
    else:
        state = "legacy-profile-migration-required"
    return {
        "schema": 1,
        "scope": SCOPE,
        "kind": "agni.probot.guest-adoption-assessment",
        "status": state,
        "activation": "blocked",
        "profile_installed": complete_profile,
        "bundle": bundle,
        "quadlets": unit_rows,
        "acl": {"sha256": digest(acl), "identity_line_sha256": {k: identities[k] for k in HOST_IDENTITIES}},
        "redis_config_sha256": digest(redis_conf),
        "base_credentials_present": base_credentials,
        "missing_roles": missing,
        "prerequisites": {
            "explicit_migration_from_legacy_two_role_installer": state == "legacy-profile-migration-required",
            "preserve_publisher_subscriber": True,
            "new_application_credentials_must_remain_guest_private": True,
            "existing_redis_must_not_restart_during_assessment": True,
        },
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--scope", required=True)
    parser.add_argument("--base", type=Path, required=True)
    parser.add_argument("--units", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--bundle")
    args = parser.parse_args()
    if args.scope != SCOPE:
        raise SystemExit("Unsupported guest scope")
    if args.bundle and not re.fullmatch(r"/nix/store/[a-z0-9]{32}-candidate", args.bundle):
        raise SystemExit("Invalid pinned bundle")
    if os.geteuid() == 0:
        raise SystemExit("Rootless guest required")
    active = set()
    for role in ROLES:
        status = subprocess.run(["systemctl", "--user", "is-active", "--quiet", SCOPE + "-" + role + ".service"],
                                check=False)
        if status.returncode == 0:
            active.add(role)
    if "redis" not in active:
        raise SystemExit("Redis must remain active during adoption assessment")
    assessment = assess(args.base, args.units, active, bundle=args.bundle)
    state_root = args.output_dir
    output = (json.dumps(assessment, indent=2, sort_keys=True) + "\n").encode()
    key = hashlib.sha256(output).hexdigest()
    destination = state_root / (key + ".json")
    state_root.mkdir(parents=True, exist_ok=True, mode=0o700)
    if destination.exists():
        if destination.is_symlink() or destination.read_bytes() != output:
            raise SystemExit("Existing assessment fingerprint does not match")
    else:
        fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "wb") as handle:
            handle.write(output)
    print("AGNI_PROBOT_ADOPTION_ASSESSMENT_PATH=" + str(destination))
    print("AGNI_PROBOT_ADOPTION_ASSESSMENT=passed state=" + assessment["status"] +
          " units=" + str(len(assessment["quadlets"])) + " redis=active activation=blocked")


if __name__ == "__main__":
    main()
