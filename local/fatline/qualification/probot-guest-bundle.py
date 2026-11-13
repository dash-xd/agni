#!/usr/bin/env python3
"""Assemble a non-secret, exact-source VM1 candidate for read-only guest transport."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil

COMPONENTS = {"skymill", "logma", "probot-runtime"}

def assemble(artifacts_path, sources_path, policy_path, plan_path, output):
    artifacts = json.loads(artifacts_path.read_text())
    sources = json.loads(sources_path.read_text())
    policy = json.loads(policy_path.read_text())
    plan = json.loads(plan_path.read_text())
    if artifacts.get("schema") != sources.get("schema") != 1:
        raise ValueError("Unsupported source schema")
    if sources.get("schema") != 1 or sources.get("scenario") != "probot-webhook":
        raise ValueError("Unexpected source selection")
    if artifacts.get("system") != "aarch64-linux" or artifacts.get("ghxd_credentials_included") is not False:
        raise ValueError("Unqualified artifact manifest")
    if set(sources["sources"]) != COMPONENTS or set(artifacts["artifacts"]) != COMPONENTS:
        raise ValueError("Incomplete exact-SHA component selection")
    for role in COMPONENTS:
        expected = sources["sources"][role]["revision"]
        item = artifacts["artifacts"][role]
        if not re.fullmatch(r"[0-9a-f]{40}", expected) or item.get("revision") != expected:
            raise ValueError("Source revision differs from artifact: " + role)
        if not re.fullmatch(r"/nix/store/[0-9a-z]{32}-[A-Za-z0-9._+-]+", item.get("store", "")):
            raise ValueError("Invalid store artifact: " + role)
    node = artifacts.get("node", "")
    if not re.fullmatch(r"/nix/store/[0-9a-z]{32}-[A-Za-z0-9._+-]+/bin/node", node):
        raise ValueError("Expected Nix-store Node executable")
    if policy.get("schema") != 1 or policy.get("scope") != "fatline-arm-vm1":
        raise ValueError("Unexpected Redis policy scope")
    if plan.get("schema") != 1 or plan.get("scope") != "fatline-arm-vm1" or plan.get("activation") != "blocked-until-role-env-redis-acl-and-github-app-secrets-bound":
        raise ValueError("Unexpected guest-plan authority")
    if plan.get("source_revisions") != {role: sources["sources"][role]["revision"] for role in COMPONENTS}:
        raise ValueError("Guest plan source revision mismatch")
    if set(policy.get("users", {})) != {"logma","skymill","bootstrap","probot_state","lifecycle_publish","lifecycle_subscribe"}:
        raise ValueError("Unexpected Redis ACL identities")
    if output.exists():
        raise ValueError("Refusing to overwrite a candidate bundle")
    output.mkdir(parents=True, mode=0o700)
    paths = {"artifacts.json": artifacts_path, "sources.json": sources_path,
             "policy.json": policy_path, "guest-plan.json": plan_path}
    checksums = []
    for name, source in sorted(paths.items()):
        destination = output / name
        shutil.copyfile(source, destination)
        checksums.append(hashlib.sha256(destination.read_bytes()).hexdigest() + "  " + name)
    rows = []
    for role, basename in [("skymill","skymill-http"),("logma","logma-lifecycle"),("probot-runtime","probot")]:
        store = artifacts["artifacts"][role]["store"]
        if not store.endswith("-" + basename):
            raise ValueError("Wrong store basename: " + role)
        rows.append("\t".join([role, store, sources["sources"][role]["revision"]]))
    rows.append("\t".join(["node", node, "node"]))
    (output / "artifacts.tsv").write_text("\n".join(rows) + "\n")
    checksums.append(hashlib.sha256((output / "artifacts.tsv").read_bytes()).hexdigest() + "  artifacts.tsv")
    (output / "SHA256SUMS").write_text("\n".join(checksums) + "\n")
    print("AGNI_PROBOT_GUEST_BUNDLE=assembled roles=3 credentials=excluded activation=blocked")

def main():
    parser = argparse.ArgumentParser()
    for name in ("artifacts","sources","policy","plan","output"):
        parser.add_argument("--"+name, required=True, type=Path)
    args = parser.parse_args()
    assemble(args.artifacts,args.sources,args.policy,args.plan,args.output)

if __name__ == "__main__":
    main()
