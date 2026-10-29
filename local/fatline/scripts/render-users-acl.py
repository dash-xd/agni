#!/usr/bin/env python3
"""Render Agni's Fatline Redis ACL from tracked policy and host-only secrets."""
import base64
import hashlib
import json
import os
import re
import sys
from pathlib import Path


IDENTIFIER = re.compile(r"^[A-Za-z0-9_.-]{1,64}$")
COMMAND = re.compile(r"^[a-z][a-z0-9|.-]*$")


def fail(message):
    raise SystemExit(message)


def main():
    if len(sys.argv) != 4:
        fail("usage: render-users-acl.py POLICY CREDENTIAL_DIR OUTPUT")
    policy_path, secret_dir, output_path = map(Path, sys.argv[1:])
    policy_bytes = policy_path.read_bytes()
    policy = json.loads(policy_bytes)
    scope = policy.get("scope", "")
    stream = policy.get("skymillStream", "")
    if policy.get("schema") != 1 or not IDENTIFIER.fullmatch(scope):
        fail("invalid Fatline ACL policy schema or scope")
    if stream != f"{scope}:skymill:stream:github.webhooks":
        fail("Skymill stream must be the configured scoped webhook stream")
    revisions = policy.get("componentRevisions", {})
    if set(revisions) != {"logma", "skymill", "ratelimiter"} or any(
        not re.fullmatch(r"[0-9a-f]{40}", sha) for sha in revisions.values()
    ):
        fail("ACL policy must pin Logma, Skymill, and Ratelimiter revisions")
    encoded = base64.urlsafe_b64encode(stream.encode()).decode().rstrip("=")
    substitutions = {"scope": scope, "stream": stream, "encodedStream": encoded}
    lines = ["user default off"]
    for name in ("logma", "skymill", "bootstrap"):
        spec = policy.get("users", {}).get(name)
        if not isinstance(spec, dict):
            fail(f"missing {name} policy")
        try:
            secret = (secret_dir / name).read_text(encoding="utf-8").strip()
        except OSError as exc:
            fail(f"cannot read {name} credential: {exc}")
        if len(secret) < 32 or any(ch.isspace() for ch in secret):
            fail(f"{name} credential must be at least 32 non-whitespace characters")
        rules = ["on", "#" + hashlib.sha256(secret.encode()).hexdigest(), "-@all", "resetkeys", "resetchannels"]
        for field, prefix in (("keys", "~"), ("channels", "&")):
            for pattern in spec.get(field, []):
                for key, value in substitutions.items():
                    pattern = pattern.replace("{" + key + "}", value)
                if "{" in pattern or "}" in pattern or any(ch.isspace() for ch in pattern):
                    fail(f"invalid {field} pattern in {name} policy")
                rules.append(prefix + pattern)
        for command in spec.get("commands", []):
            if not COMMAND.fullmatch(command):
                fail(f"invalid command {command!r} in {name} policy")
            rules.append("+" + command)
        lines.append("user " + name + " " + " ".join(rules))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    temporary = output_path.with_name(output_path.name + ".tmp")
    temporary.write_text("\n".join(lines) + "\n", encoding="utf-8")
    os.chmod(temporary, 0o644)
    temporary.replace(output_path)
    policy_digest = hashlib.sha256(policy_bytes).hexdigest()
    evidence = {
        "schema": 1,
        "scope": scope,
        "skymillStream": stream,
        "policySha256": policy_digest,
        "componentRevisions": revisions,
    }
    evidence_path = output_path.with_suffix(output_path.suffix + ".evidence.json")
    evidence_path.write_text(json.dumps(evidence, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    os.chmod(evidence_path, 0o644)
    print(policy_digest)


if __name__ == "__main__":
    main()
