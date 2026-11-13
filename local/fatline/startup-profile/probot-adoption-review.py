#!/usr/bin/env python3
"""Compare immutable VM1 legacy assessment to the selected qualified bundle."""
import argparse
import hashlib
import json
from pathlib import Path
import re

SHA = re.compile(r"[0-9a-f]{64}\.json")
STORE = re.compile(r"/nix/store/[a-z0-9]{32}-[A-Za-z0-9._+-]+")


def review(report, candidate):
    if report.get("schema") != 1 or report.get("kind") != "agni.probot.guest-adoption-assessment":
        raise ValueError("Unsupported adoption evidence")
    if report.get("scope") != "fatline-arm-vm1" or report.get("activation") != "blocked":
        raise ValueError("Unexpected migration scope or activation authority")
    if report.get("bundle") != candidate.get("bundle"):
        raise ValueError("Assessment does not reference selected immutable candidate")
    if not report.get("acl", {}).get("sha256") or set(report.get("acl", {}).get("identity_line_sha256", {})) != {"default", "publisher", "subscriber"}:
        raise ValueError("Incomplete preserved host-link fingerprint")
    existing = report.get("quadlets", {})
    if not {"redis", "nginx"} <= set(existing):
        raise ValueError("Base Redis/NGINX units missing")
    artifacts = candidate["artifacts"]
    if set(artifacts) != {"logma", "skymill", "probot-runtime", "node"}:
        raise ValueError("Unexpected candidate component set")
    current = {}
    for role in ("redis", "nginx", "logma", "skymill", "probot"):
        item = existing.get(role)
        if item is None:
            current[role] = {"present": False, "active": False, "store_references": []}
            continue
        refs = item.get("store_references", [])
        if not isinstance(refs, list) or not all(re.fullmatch(STORE.pattern + r"(?:/[A-Za-z0-9._+-]+)*", x) for x in refs):
            raise ValueError("Invalid observed store references")
        current[role] = {"present": True, "active": item.get("active") is True, "store_references": refs}
    selected = {role: artifacts[role]["path"] for role in artifacts}
    for item in selected.values():
        if not re.fullmatch(STORE.pattern + r"(?:/bin/node)?", item):
            raise ValueError("Invalid selected store path")
    comparisons = {}
    for role, key in (("logma", "logma"), ("skymill", "skymill"), ("probot", "probot-runtime")):
        refs = current[role]["store_references"]
        target = selected[key]
        comparisons[role] = {"candidate_store": target,
                             "already_selected": any(value == target or value.startswith(target + "/") for value in refs),
                             "observed_store_references": refs}
    base_credentials = report.get("base_credentials_present", {})
    if set(base_credentials) != {"logma", "skymill", "bootstrap"}:
        raise ValueError("Incomplete credential presence assessment")
    return {
        "schema": 1,
        "kind": "agni.probot.legacy-migration-review",
        "scope": "fatline-arm-vm1",
        "state": report["status"],
        "activation": "blocked",
        "bundle": report["bundle"],
        "existing_roles": current,
        "selected_components": comparisons,
        "selected_node": selected["node"],
        "base_credentials_present": base_credentials,
        "consolidated_profile_installed": report.get("profile_installed") is True,
        "next_boundary": "qualify-controlled-profile-migration" if report["status"] == "legacy-profile-migration-required" else "review-runtime-state",
        "redis_restart": "not-performed",
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--assessment", type=Path, required=True)
    parser.add_argument("--bundle", type=Path, required=True)
    parser.add_argument("--bundle-store", required=True)
    args = parser.parse_args()
    if not SHA.fullmatch(args.assessment.name):
        raise SystemExit("Expected content-addressed evidence filename")
    data = args.assessment.read_bytes()
    if hashlib.sha256(data).hexdigest() != args.assessment.stem:
        raise SystemExit("Assessment checksum mismatch")
    report = json.loads(data)
    if not re.fullmatch(r"/nix/store/[0-9a-z]{32}-candidate", args.bundle_store):
        raise SystemExit("Invalid candidate store identity")
    values = {}
    for line in (args.bundle / "artifacts.tsv").read_text().splitlines():
        parts = line.split("\t")
        if len(parts) != 3 or parts[0] in values:
            raise SystemExit("Malformed candidate artifact record")
        values[parts[0]] = {"path": parts[1], "revision": parts[2]}
    output = review(report, {"bundle": args.bundle_store, "artifacts": values})
    print(json.dumps(output, sort_keys=True, indent=2))
    print("AGNI_PROBOT_ADOPTION_REVIEW=passed state=" + output["state"] +
          " activation=blocked redis_restart=none")


if __name__ == "__main__":
    main()
