#!/usr/bin/env python3
"""Shoal stopped-guest backup preflight contract tests."""
import tempfile
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
import backup


class BackupTests(unittest.TestCase):
    def test_manifest_overlay_and_digest(self):
        with tempfile.TemporaryDirectory() as tmp:
            state = Path(tmp) / "starwisp"
            state.mkdir()
            (state / "overlay.qcow2").write_bytes(b"QCOW")
            (state / "build.txt").write_text(
                "disk_sha256=" + "a" * 64 +
                "\nrunner=sha256:" + "b" * 64 +
                "\nshared_nix_volume=nix-xd-arm-store\n")
            (state / "manifest.txt").write_text(
                "container_id=" + "c" * 64 +
                "\nport=2222\nrunner=sha256:" + "b" * 64 + "\n")
            result = backup.inspect_state("farcaster", Path(tmp),
                                          {"instance": "starwisp", "sshPort": 2222},
                                          {"containerId": "c" * 64, "bootId": "boot"})
            self.assertEqual(result["overlaySizeBytes"], 4)
            self.assertEqual(result["bootId"], "boot")

    def test_manifest_mismatch_refused(self):
        with tempfile.TemporaryDirectory() as tmp:
            state = Path(tmp) / "starwisp"
            state.mkdir()
            (state / "overlay.qcow2").write_bytes(b"QCOW")
            (state / "build.txt").write_text(
                "disk_sha256=abc\nrunner=sha256:123\nshared_nix_volume=nix-xd-arm-store\n")
            (state / "manifest.txt").write_text("container_id=incorrect\nport=2222\n")
            with self.assertRaisesRegex(ValueError, "managed manifest"):
                backup.inspect_state("farcaster", Path(tmp),
                                     {"instance": "starwisp", "sshPort": 2222},
                                     {"containerId": "actual", "bootId": "boot"})

    def test_never_stops_or_copies_guest(self):
        source = (ROOT / "backup.py").read_text()
        self.assertNotIn("podman stop", source)
        self.assertNotIn("shutil.copy", source)
        self.assertNotIn("loginctl poweroff", source)
        self.assertIn("CanPowerOff", source)
        self.assertIn("not-created", source)


if __name__ == "__main__":
    unittest.main()
