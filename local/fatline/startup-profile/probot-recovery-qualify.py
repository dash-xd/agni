#!/usr/bin/env python3
"""Restore a verified private baseline in a disposable directory; never touch live units."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil

SCOPE = "fatline-arm-vm1"
ROLES = ("redis", "nginx", "logma", "skymill")
SHA256 = re.compile(r"[0-9a-f]{64}")


def restore_category(plan, category, target):
    entries = plan["rollback_checksums"][category]
    if not isinstance(entries, dict):
        raise ValueError("Invalid rollback manifest: " + category)
    saved = Path(plan["_directory"]) / "rollback" / category
    for name, sha in sorted(entries.items()):
        relative = Path(name)
        if relative.is_absolute() or ".." in relative.parts or not SHA256.fullmatch(sha):
            raise ValueError("Invalid rollback filename/digest")
        origin = saved / relative
        if origin.is_symlink() or not origin.is_file() or hashlib.sha256(origin.read_bytes()).hexdigest() != sha:
            raise ValueError("Rollback snapshot integrity mismatch: " + name)
        output = target / relative
        output.parent.mkdir(parents=True, mode=0o700, exist_ok=True)
        with origin.open("rb") as infile, output.open("xb") as outfile:
            shutil.copyfileobj(infile, outfile)
        output.chmod(0o600)
        if hashlib.sha256(output.read_bytes()).hexdigest() != sha:
            raise ValueError("Restored content mismatch: " + name)


def systemd_graph(quadlets):
    graph = {}
    for role in ROLES:
        path = quadlets / (SCOPE + "-" + role + ".container")
        if not path.is_file() or path.is_symlink():
            raise ValueError("Legacy unit missing: " + role)
        data = path.read_text()
        section = None
        fields = {}
        for raw in data.splitlines():
            row = raw.strip()
            if not row or row.startswith("#"):
                continue
            if row.startswith("[") and row.endswith("]"):
                section = row[1:-1]
            elif section == "Unit" and "=" in row:
                key, value = row.split("=", 1)
                fields.setdefault(key, set()).update(value.split())
        if "[Container]" not in data:
            raise ValueError("Not a Quadlet: " + role)
        graph[role] = fields
    # The legacy graph is authoritative: it is checksum-pinned by the
    # adoption assessment and the recovery manifest. Do not impose the
    # consolidated five-role dependency graph on these older units.
    permitted = {SCOPE + "-" + role + ".service" for role in ROLES}
    for role, fields in graph.items():
        own = SCOPE + "-" + role + ".service"
        for field in ("Requires", "Wants", "After", "Before", "BindsTo", "PartOf", "Upholds"):
            for unit in fields.get(field, set()):
                if unit == own:
                    raise ValueError("Recovered service self-dependency: " + role)
                if unit == SCOPE + "-probot.service":
                    raise ValueError("Recovered graph references staged Probot")
                if unit.startswith(SCOPE + "-") and unit.endswith(".service") and unit not in permitted:
                    raise ValueError("Unexpected scoped recovered dependency: " + unit)
    if (quadlets / (SCOPE + "-probot.container")).exists():
        raise ValueError("Recovered graph unexpectedly includes Probot")


def recover(plan_dir, output, generation):
    plan_dir = Path(plan_dir)
    if not re.fullmatch(r"[a-f0-9]{64}-[a-z0-9]{32}-candidate", generation):
        raise ValueError("Invalid generation identifier")
    if output.exists():
        raise ValueError("Recovery destination must not exist")
    plan_path = plan_dir / "plan.json"
    if plan_path.is_symlink() or not plan_path.is_file():
        raise ValueError("Missing private activation plan")
    plan = json.loads(plan_path.read_text())
    if plan.get("schema") != 1 or plan.get("kind") != "agni.deployment.activation-plan":
        raise ValueError("Invalid activation plan")
    if plan.get("scope") != SCOPE or plan.get("generation") != generation:
        raise ValueError("Activation plan/generation mismatch")
    if plan.get("activation", {}).get("allowed") is not False or plan.get("rollback", {}).get("executed") is not False:
        raise ValueError("Recovery cannot use an already activated plan")
    plan["_directory"] = str(plan_dir)
    output.mkdir(mode=0o700, parents=True)
    for category, path in (("quadlets", "quadlets"), ("config", "config"), ("credentials", "credentials")):
        restore_category(plan, category, output / path)
    recovered_units = output / "quadlets"
    required = {SCOPE + "-" + r + ".container" for r in ROLES} | {SCOPE + ".network"}
    if not all((recovered_units / name).is_file() for name in required):
        raise ValueError("Recovered four-role unit set incomplete")
    for category in ("config", "credentials"):
        if not list((output / category).rglob("*")):
            raise ValueError("Recovered " + category + " unexpectedly empty")
    systemd_graph(recovered_units)
    return {"roles": 4, "config": "restored", "credentials": "restored",
            "graph": "validated", "activation": "blocked"}


def main():
    parser = argparse.ArgumentParser()
    for name in ("plan-dir", "output", "generation"):
        parser.add_argument("--" + name, required=True)
    args = parser.parse_args()
    recover(args.plan_dir, Path(args.output), args.generation)
    print("AGNI_RECOVERY_RESTORE=passed roles=4 snapshot=exact isolated=true activation=blocked")
    print("AGNI_RECOVERY_GRAPH=passed roles=4 config=restored credentials=restored")


if __name__ == "__main__":
    main()
