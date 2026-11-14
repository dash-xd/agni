#!/usr/bin/env python3
"""Repair the installed disposable VM1 Skymill bearer credential after partial cutover."""
import argparse
import json
import os
from pathlib import Path
import re
import tempfile

SCOPE = "fatline-arm-vm1"
TOKEN = re.compile(rb"[0-9a-f]{64}")

def repair(base, generation):
    apps = base / "services"
    staged = apps / "probot-migrations" / generation
    if not re.fullmatch(r"[a-f0-9]{64}-[a-z0-9]{32}-candidate", generation):
        raise ValueError("Invalid selected generation")
    if staged.is_symlink() or not staged.is_dir():
        raise ValueError("Missing immutable migration generation")
    manifest = staged / "rendered" / "manifest.json"
    installed = apps / "profile" / "manifest.json"
    if manifest.is_symlink() or installed.is_symlink() or not manifest.is_file() or installed.read_bytes() != manifest.read_bytes():
        raise ValueError("Installed profile is not the selected generation")
    if json.loads(installed.read_text()).get("scope") != SCOPE:
        raise ValueError("Invalid installed scope")
    names = [
        apps / "credentials" / "skymill" / "http-token",
        apps / "credentials" / "probot" / "skymill-token",
    ]
    originals = []
    for path in names:
        if path.is_symlink() or not path.is_file() or path.stat().st_mode & 0o077:
            raise ValueError("Invalid private credential path/mode")
        originals.append(path.read_bytes())
    if originals[0] != originals[1]:
        raise ValueError("Skymill/Probot HTTP credential mismatch")
    token = originals[0].removesuffix(b"\n")
    if not TOKEN.fullmatch(token) or originals[0] not in (token, token + b"\n"):
        raise ValueError("Unexpected HTTP credential bytes")
    if originals[0] == token:
        return "already-normalized"
    for path in names:
        fd, tmp = tempfile.mkstemp(prefix=".http-token-", dir=path.parent)
        try:
            with os.fdopen(fd, "wb") as output:
                output.write(token)
                output.flush()
                os.fsync(output.fileno())
            os.chmod(tmp, 0o600)
            os.replace(tmp, path)
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)
    return "normalized"

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", type=Path, required=True)
    parser.add_argument("--generation", required=True)
    args = parser.parse_args()
    print("AGNI_SANDBOX_HTTP_CREDENTIAL=passed action=" + repair(args.base, args.generation))
