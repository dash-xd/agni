#!/usr/bin/env python3
"""Verify exact local execution dependencies before staging; no network."""
import json
import re
import subprocess
import sys
from pathlib import Path

fatline = Path(__file__).resolve().parents[1]
manifest = json.loads((fatline / "qualification/architecture-sources.json").read_text())

def fail(reason):
    raise SystemExit("AGNI_ARCHITECTURE_SOURCES=blocked reason=" + reason)

def git(root, *args):
    return subprocess.check_output(
        ["git", "-C", str(root), *args], text=True, stderr=subprocess.DEVNULL
    ).strip()

if len(sys.argv) != 3:
    fail("usage-nix-xd-dir-smoke-dir")
nix, smoke = (Path(p).resolve() for p in sys.argv[1:])
if manifest.get("schema") != 1 or set(manifest.get("sources", {})) != {"nix-xd", "smoke"}:
    fail("invalid-source-lock")
for name, root in (("nix-xd", nix), ("smoke", smoke)):
    entry = manifest["sources"][name]
    expected = entry.get("revision", "")
    if not isinstance(expected, str) or not re.fullmatch(r"[0-9a-f]{40}", expected):
        fail("invalid-revision-" + name)
    if root.name != entry.get("checkout"):
        fail("unexpected-checkout-" + name)
    try:
        actual = git(root, "rev-parse", "HEAD")
        dirty = git(root, "status", "--porcelain", "--untracked-files=no")
    except (OSError, subprocess.CalledProcessError):
        fail("missing-checkout-" + name)
    if actual != expected:
        fail("wrong-revision-" + name + " expected=" + expected + " actual=" + actual)
    if dirty:
        fail("dirty-checkout-" + name)
    print("AGNI_ARCHITECTURE_SOURCE=passed name=" + name + " revision=" + expected)
print("AGNI_ARCHITECTURE_SOURCES=passed exact=true")
