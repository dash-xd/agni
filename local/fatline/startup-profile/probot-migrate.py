#!/usr/bin/env python3
"""Resolve and stage a legacy VM1 five-role migration without touching active units."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re

ROLES = ("redis", "nginx", "logma", "skymill")
BASE = "fatline-arm-vm1"
SHA64 = re.compile(r"[0-9a-f]{64}")
STORE = r"/nix/store/[a-z0-9]{32}-[A-Za-z0-9._+-]+"
BIN = re.compile(STORE + r"/bin/[A-Za-z0-9._+-]+")
NIX = re.compile(STORE)


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def build_spec(assessment, unit_dir, acl, metadata, home, bundle, archive):
    if assessment.get("schema") != 1 or assessment.get("kind") != "agni.probot.guest-adoption-assessment":
        raise ValueError("Unsupported adoption evidence")
    if assessment.get("status") != "legacy-profile-migration-required" or assessment.get("scope") != BASE:
        raise ValueError("Legacy VM1 migration assessment required")
    if assessment.get("activation") != "blocked" or assessment.get("profile_installed") is not False:
        raise ValueError("Assessment already claims profile authority")
    if home not in ("/var/home/wisp", "/home/wisp"):
        raise ValueError("Unexpected rootless guest home")
    if not NIX.fullmatch(bundle) or not NIX.fullmatch(archive):
        raise ValueError("Resolved Nix bundle/archive paths required")
    if hashlib.sha256(acl.read_bytes()).hexdigest() != assessment["acl"]["sha256"]:
        raise ValueError("Redis ACL changed after adoption assessment")
    existing = {}
    for line in acl.read_text().splitlines():
        fields = line.split()
        if len(fields) < 3 or fields[0] != "user" or fields[1] in existing:
            raise ValueError("Invalid existing ACL identities")
        existing[fields[1]] = hashlib.sha256(line.encode()).hexdigest()
    for name, value in assessment["acl"]["identity_line_sha256"].items():
        if existing.get(name) != value:
            raise ValueError("Host-link ACL identity changed: " + name)
    if set(assessment.get("base_credentials_present", {})) != {"logma", "skymill", "bootstrap"} or not all(assessment["base_credentials_present"].values()):
        raise ValueError("Legacy application credentials are incomplete")
    observed = assessment.get("quadlets", {})
    if not set(ROLES) <= set(observed):
        raise ValueError("Legacy four-role service graph incomplete")
    for role in ROLES:
        file = unit_dir / (BASE + "-" + role + ".container")
        if file.is_symlink() or not file.is_file() or hashlib.sha256(file.read_bytes()).hexdigest() != observed[role]["sha256"]:
            raise ValueError("Quadlet changed after adoption assessment: " + role)
        if observed[role]["active"] is not True:
            raise ValueError("Legacy service was not active: " + role)
    if not isinstance(metadata, dict) or not BIN.fullmatch(metadata.get("probe", "")):
        raise ValueError("Pinned Agni bootstrap probe missing")
    def executable(role, suffix):
        refs = observed[role]["store_references"]
        choices = [p for p in refs if BIN.fullmatch(p) and p.endswith("/bin/" + suffix)]
        if len(choices) != 1:
            raise ValueError("Unable to uniquely resolve legacy " + role + " executable")
        return choices[0]
    nginx_unit = (unit_dir / (BASE + "-nginx.container")).read_text()
    ports = re.findall(r"(?m)^PublishPort=127\.0\.0\.1:([0-9]{4,5}):6379$", nginx_unit)
    if len(ports) != 1:
        raise ValueError("Legacy Nginx loopback proxy binding is not unambiguous")
    port = int(ports[0])
    if not 1024 <= port <= 65535:
        raise ValueError("Invalid scoped Redis proxy port")
    return {"schema": 1, "scope": BASE, "home": home, "port": port,
            "bundle": bundle, "archive": archive, "probe": metadata["probe"],
            "redis": executable("redis", "redis-server"),
            "nginx": executable("nginx", "nginx"),
            "logma": executable("logma", "api"),
            "skymill": executable("skymill", "skymill-http"),
            "aclDigest": hashlib.sha256(acl.read_bytes()).hexdigest()}


def main():
    parser = argparse.ArgumentParser()
    for name in ("assessment", "unit-dir", "acl", "credentials", "metadata",
                 "paths", "bundle-store", "candidate", "home",
                 "output", "acl-renderer", "credential-generator",
                 "profile-renderer", "base-renderer", "stage-helper"):
        parser.add_argument("--" + name, required=True)
    args = parser.parse_args()
    assessment_path = Path(args.assessment)
    raw = assessment_path.read_bytes()
    if not SHA64.fullmatch(assessment_path.stem) or hashlib.sha256(raw).hexdigest() != assessment_path.stem:
        raise ValueError("Adoption evidence content digest mismatch")
    assessment = json.loads(raw)
    if assessment.get("bundle") != args.bundle_store:
        raise ValueError("Adoption evidence references a different pinned candidate")
    source = Path(args.candidate)
    if not (source / "artifacts.json").is_file() or not (source / "policy.json").is_file():
        raise ValueError("Pinned application candidate incomplete")
    paths = json.loads(Path(args.paths).read_text())
    if set(paths) != {"bundle", "archive"}:
        raise ValueError("Unexpected migration bootstrap dependencies")
    spec = build_spec(assessment, Path(args.unit_dir), Path(args.acl),
                      json.loads(Path(args.metadata).read_text()), args.home, paths["bundle"], paths["archive"])
    target = Path(args.output)
    if target.exists():
        raise ValueError("Migration candidate already exists; never overwrite a private generation")
    target.mkdir(mode=0o700, parents=True)
    inputs = target / "input"
    inputs.mkdir(mode=0o700)
    spec_path = inputs / "spec.json"
    spec_path.write_text(json.dumps(spec, sort_keys=True, indent=2) + "\n")
    spec_path.chmod(0o600)
    for name in ("artifacts", "sources", "policy"):
        output = inputs / (name + ".json")
        output.write_bytes((source / (name + ".json")).read_bytes())
        output.chmod(0o600)
    stage = load("agni_probot_migration_stager", Path(args.stage_helper))
    stage.stage(spec_path, inputs / "artifacts.json", inputs / "sources.json",
                inputs / "policy.json", Path(args.acl), Path(args.credentials),
                target / "rendered", Path(args.acl_renderer), Path(args.credential_generator),
                Path(args.profile_renderer), Path(args.base_renderer))
    rendered = target / "rendered"
    expected = [rendered / (BASE + "-" + role + ".container") for role in (*ROLES, "probot")]
    if not all(path.is_file() for path in expected):
        raise ValueError("Five-role Quadlet render incomplete")
    candidate_acl = (rendered / "users.acl").read_text().splitlines()
    prior_acl = Path(args.acl).read_text().splitlines()
    for principal in ("publisher", "subscriber"):
        old = [line for line in prior_acl if line.split()[:2] == ["user", principal]]
        new = [line for line in candidate_acl if line.split()[:2] == ["user", principal]]
        if len(old) != 1 or new != old:
            raise ValueError("Host-link ACL identity mutated: " + principal)
    print("AGNI_PROBOT_MIGRATION_STAGE=passed roles=5 host_link=preserved activation=blocked")
    print("AGNI_PROBOT_MIGRATION_CANDIDATE=" + str(target))


if __name__ == "__main__":
    main()
