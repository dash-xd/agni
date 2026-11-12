#!/usr/bin/env python3
"""Stage a five-role VM1 profile using the guest's existing private credentials."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def stage(spec_path, artifacts_path, sources_path, policy_path, old_acl,
          old_credentials, output, acl_renderer, generator_path, profile_path, base_renderer):
    if output.exists():
        raise ValueError("Candidate already exists; use a fresh generation")
    spec = json.loads(spec_path.read_text())
    artifacts = json.loads(artifacts_path.read_text())
    sources = json.loads(sources_path.read_text())
    if spec.get("schema") != 1 or spec.get("scope") != "fatline-arm-vm1":
        raise ValueError("Expected exact VM1 profile")
    if spec.get("home") != "/home/wisp":
        raise ValueError("Guest profile must resolve to rootless wisp home")
    if sources.get("schema") != 1 or sources.get("scenario") != "probot-webhook":
        raise ValueError("Expected exact webhook source manifest")
    if artifacts.get("ghxd_credentials_included") is not False:
        raise ValueError("Application artifacts must not contain GHXD credentials")

    output.mkdir(mode=0o700, parents=True)
    generator = load("agni_probot_generator_stage", generator_path)
    profile = load("agni_probot_renderer_stage", profile_path)
    base = load("agni_base_renderer_stage", base_renderer)
    private = output / ".generation"
    generator.generate(policy_path, old_acl, old_credentials, private, acl_renderer)
    spec["aclDigest"] = (private / "digest").read_text().strip()
    profile.render(spec, artifacts, sources, output, base.render)
    for role in ("logma", "skymill", "bootstrap", "probot"):
        shutil.copytree(private / "credentials" / role, output / role)
    shutil.copy2(private / "users.acl", output / "users.acl")
    os.chmod(output / "users.acl", 0o600)
    if (output / "skymill" / "http-token").read_bytes() != (output / "probot" / "skymill-token").read_bytes():
        raise ValueError("Mismatched Skymill HTTP client/server identity")
    shutil.rmtree(private)
    print("AGNI_PROBOT_STAGE=passed roles=5 authority=private activation=blocked")


def main():
    parser = argparse.ArgumentParser()
    for name in ("spec", "artifacts", "sources", "policy", "old-acl", "old-credentials",
                 "output", "acl-renderer", "credential-generator", "profile-renderer", "base-renderer"):
        parser.add_argument("--" + name, required=True, type=Path)
    args = parser.parse_args()
    stage(args.spec, args.artifacts, args.sources, args.policy, args.old_acl,
          args.old_credentials, args.output, args.acl_renderer, args.credential_generator,
          args.profile_renderer, args.base_renderer)


if __name__ == "__main__":
    main()
