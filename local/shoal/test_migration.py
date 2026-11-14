#!/usr/bin/env python3
"""Offline contract tests for the read-only Shoal migration staging gate."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
import migration


class MigrationTests(unittest.TestCase):
    def test_candidate_network_profiles_are_nonrouting(self):
        candidate = json.loads((ROOT / "plan.json").read_text())["networkCandidate"]
        a = migration.keyfile("farcaster", candidate["farcasterIPv4"], candidate["transitCIDR"])
        b = migration.keyfile("world1", candidate["world1IPv4"], candidate["transitCIDR"])
        self.assertNotEqual(a, b)
        for profile in (a, b):
            self.assertIn("never-default=true", profile)
            self.assertIn("method=disabled", profile)
            self.assertNotIn("gateway=", profile)
            self.assertFalse(any(line.startswith("dns=") for line in profile.splitlines()))

    def test_duplicate_manifest_keys_block(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "manifest.txt"
            path.write_text("port=2222\nport=2223\n")
            with self.assertRaisesRegex(ValueError, "duplicate"):
                migration.manifest(path)

    def test_invalid_transit_address_blocks(self):
        with self.assertRaises(ValueError):
            migration.keyfile("world1", "192.0.2.2", "172.30.255.0/30")

    def test_preparation_cannot_promote_network(self):
        source = (ROOT / "migration.py").read_text()
        self.assertIn('"consistentBackup": False', source)
        self.assertIn('"not-activated"', source)
        self.assertIn("StrictHostKeyChecking=yes", source)
        self.assertNotIn("AGNI_SHOAL_NETWORK=passed", source)


if __name__ == "__main__":
    unittest.main()
