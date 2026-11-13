#!/usr/bin/env python3
"""Verify a staged VM1 generation with immutable inputs. Never activate services."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re

SCOPE = "fatline-arm-vm1"
ROLES = ("redis", "nginx", "logma", "skymill", "probot")
STORE = re.compile(r"/nix/store/[a-z0-9]{32}-[A-Za-z0-9._+-]+")
SHA = re.compile(r"[0-9a-f]{64}")


def read_json(path):
    if path.is_symlink() or not path.is_file():
        raise ValueError("Missing or symlinked generation input: " + str(path))
    return json.loads(path.read_text())


def parse_systemd_sections(data):
    sections = {}
    section = None
    for raw in data.splitlines():
        line = raw.strip()
        if not line or line.startswith(("#", ";")):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1]
            sections.setdefault(section, {})
        elif section is not None and "=" in line:
            key, value = line.split("=", 1)
            sections[section].setdefault(key, []).append(value)
        else:
            raise ValueError("Malformed staged systemd directive")
    return sections


def verify(migration, assessment_path, old_acl, installed_units, store):
    migration = Path(migration)
    rendered = migration / "rendered"
    input_dir = migration / "input"
    evidence_bytes = assessment_path.read_bytes()
    if not SHA.fullmatch(assessment_path.stem) or hashlib.sha256(evidence_bytes).hexdigest() != assessment_path.stem:
        raise ValueError("Immutable adoption assessment digest mismatch")
    assessment = json.loads(evidence_bytes)
    bundle_name = assessment["bundle"].split("/")[-1]
    if migration.name != assessment_path.stem + "-" + bundle_name:
        raise ValueError("Migration identity does not match assessment bundle")
    if assessment.get("status") != "legacy-profile-migration-required" or assessment.get("profile_installed") is not False:
        raise ValueError("Migration source was not a legacy deployment")
    if assessment.get("scope") != SCOPE or assessment.get("activation") != "blocked":
        raise ValueError("Unexpected adoption authority")
    current_acl = old_acl.read_bytes()
    if hashlib.sha256(current_acl).hexdigest() != assessment["acl"]["sha256"]:
        raise ValueError("Legacy Redis ACL changed since assessment")
    if not all(role in assessment["quadlets"] and assessment["quadlets"][role]["active"] for role in ROLES[:-1]):
        raise ValueError("Incomplete observed four-role baseline")
    for role in ROLES[:-1]:
        file = installed_units / (SCOPE + "-" + role + ".container")
        if file.is_symlink() or hashlib.sha256(file.read_bytes()).hexdigest() != assessment["quadlets"][role]["sha256"]:
            raise ValueError("Installed legacy Quadlet changed: " + role)
    if (installed_units / (SCOPE + "-probot.container")).exists():
        raise ValueError("Probot is already installed")
    spec = read_json(input_dir / "spec.json")
    manifest = read_json(rendered / "manifest.json")
    artifacts = read_json(input_dir / "artifacts.json")
    sources = read_json(input_dir / "sources.json")
    if spec != manifest:
        # The renderer writes a resolved application overlay. Check immutable base
        # properties separately instead of assuming the profile is byte-identical.
        for field in ("scope", "home", "redis", "nginx", "probe", "bundle", "archive", "port"):
            if spec.get(field) != manifest.get(field):
                raise ValueError("Rendered base profile differs from selected migration spec: " + field)
    if spec.get("scope") != SCOPE or spec.get("home") not in ("/home/wisp", "/var/home/wisp"):
        raise ValueError("Unexpected guest scope/home")
    if artifacts.get("schema") != 1 or artifacts.get("system") != "aarch64-linux" or artifacts.get("ghxd_credentials_included") is not False:
        raise ValueError("Unqualified application artifact manifest")
    for role in ("logma", "skymill", "probot-runtime"):
        entry = artifacts["artifacts"][role]
        if entry["revision"] != sources["sources"][role]["revision"]:
            raise ValueError("Candidate source mismatch: " + role)
    for executable in (spec["redis"], spec["nginx"], spec["probe"], artifacts["node"]):
        if not re.fullmatch(STORE.pattern + r"/bin/[A-Za-z0-9._+-]+", executable):
            raise ValueError("Invalid pinned Nix executable")
        if not (store / executable.removeprefix("/nix/store/")).is_file():
            raise ValueError("Missing selected Nix executable: " + executable)
    for role in ("logma", "skymill"):
        path = artifacts["artifacts"][role]["store"]
        if not STORE.fullmatch(path) or not (store / path.removeprefix("/nix/store/")).is_file():
            raise ValueError("Missing candidate artifact: " + role)
    probot = artifacts["artifacts"]["probot-runtime"]["store"]
    if not STORE.fullmatch(probot) or not (store / probot.removeprefix("/nix/store/") / "router/serve.js").is_file():
        raise ValueError("Missing staged Probot router")
    for path in (spec["bundle"], spec["archive"]):
        if not STORE.fullmatch(path) or not (store / path.removeprefix("/nix/store/")).exists():
            raise ValueError("Missing pinned bootstrap dependency")
    old_lines = current_acl.decode().splitlines()
    new_lines = (rendered / "users.acl").read_text().splitlines()
    for principal in ("publisher", "subscriber"):
        old = [s for s in old_lines if s.split()[:2] == ["user", principal]]
        new = [s for s in new_lines if s.split()[:2] == ["user", principal]]
        if len(old) != 1 or new != old:
            raise ValueError("Host-link ACL identity changed: " + principal)
    if hashlib.sha256((rendered / "users.acl").read_bytes()).hexdigest() != manifest["aclDigest"]:
        raise ValueError("Candidate ACL digest mismatch")
    for role in ("logma", "skymill", "bootstrap", "probot"):
        for item in (rendered / role).iterdir():
            if item.is_symlink() or not item.is_file() or item.stat().st_mode & 0o077:
                raise ValueError("Unsafe staged credential permissions: " + role)
    if (rendered / "skymill/http-token").read_bytes() != (rendered / "probot/skymill-token").read_bytes():
        raise ValueError("Staged Skymill client/server authority mismatch")
    required = {
        "redis": {"Upholds": set(SCOPE + "-" + role + ".service" for role in ("nginx", "logma", "skymill", "probot"))},
        "nginx": {"Requires": {SCOPE + "-redis.service"}, "After": {SCOPE + "-redis.service"}},
        "logma": {"Requires": {SCOPE + "-redis.service", SCOPE + "-nginx.service"}, "After": {SCOPE + "-redis.service", SCOPE + "-nginx.service"}},
        "skymill": {"Requires": {SCOPE + "-redis.service"}, "After": {SCOPE + "-redis.service"}},
        "probot": {"Requires": {SCOPE + "-redis.service", SCOPE + "-skymill.service", SCOPE + "-logma.service"}, "After": {SCOPE + "-redis.service", SCOPE + "-skymill.service", SCOPE + "-logma.service"}},
    }
    for role in ROLES:
        file = rendered / (SCOPE + "-" + role + ".container")
        if file.is_symlink():
            raise ValueError("Symlinked staged Quadlet")
        sections = parse_systemd_sections(file.read_text())
        if "Container" not in sections or "Unit" not in sections:
            raise ValueError("Incomplete Quadlet sections: " + role)
        for field, values in required[role].items():
            actual = set(word for entry in sections["Unit"].get(field, []) for word in entry.split())
            if not values <= actual:
                raise ValueError("Missing dependency: " + role + "." + field)
        source = file.read_text()
        if "ReadOnly=true" not in source or "Volume=/var/mnt/nixstore:/nix/store:ro" not in source:
            raise ValueError("Missing read-only isolation: " + role)
        if role not in ("nginx",) and "PublishPort=" in source:
            raise ValueError("Unexpected publicly bound service: " + role)
    if "PROBOT_RUNTIME_WORKER_ENABLED=false" not in (rendered / (SCOPE + "-probot.container")).read_text():
        raise ValueError("Live Probot worker must remain disabled")
    if not (rendered / (SCOPE + ".network")).is_file():
        raise ValueError("Staged network definition missing")
    return {"roles": len(ROLES), "legacy": "preserved", "store": "visible",
            "quadlet": "validated", "activation": "blocked",
            "rollback": "baseline-available-not-executed"}


def main():
    p = argparse.ArgumentParser()
    for name in ("migration", "assessment", "old-acl", "installed-units", "store"):
        p.add_argument("--" + name, type=Path, required=True)
    a = p.parse_args()
    result = verify(a.migration, a.assessment, a.old_acl, a.installed_units, a.store)
    print("AGNI_PROBOT_MIGRATION_CONTENT=passed roles=5 store=visible legacy=preserved activation=blocked")
    print("AGNI_PROBOT_ROLLBACK_PREFLIGHT=passed baseline=available execution=not-tested")


if __name__ == "__main__":
    main()
