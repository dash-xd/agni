#!/usr/bin/env python3
import hashlib
import json
import tempfile
from pathlib import Path
import unittest
import backup_verify


class VerifyTests(unittest.TestCase):
    def archive(self, parent):
        path = parent / "staging"
        path.mkdir()
        base = path / "base.qcow2"
        base.write_bytes(b"base")
        digest = backup_verify.sha256(base)
        guests = {}
        for name in backup_verify.STAGES:
            folder = path / name
            folder.mkdir()
            (folder / "overlay.qcow2").write_bytes(name.encode())
            (folder / "build.txt").write_text(
                "disk_sha256=" + digest + "\nrunner=sha256:" + "a" * 64 + "\n")
            (folder / "manifest.txt").write_text(
                "container_id=" + "b" * 64 + "\nrunner=sha256:" + "a" * 64 + "\n")
            (folder / "config.ign").write_text("{}")
            (folder / "known_hosts").write_text("ssh-ed25519 fixture")
            guests[name] = {
                "overlaySha256": backup_verify.sha256(folder / "overlay.qcow2"),
                "overlaySizeBytes": len(name), "baseSha256": digest,
                "containerId": "b" * 64}
        receipt = {"schemaVersion": 1, "stage": "network-offline-backup",
                   "planSha256": "c" * 64, "guests": guests}
        raw = (json.dumps(receipt) + "\n").encode()
        (path / "receipt.json").write_bytes(raw)
        destination = parent / ("shoal-" + hashlib.sha256(raw).hexdigest())
        path.rename(destination)
        return destination

    def test_valid_archive_is_not_a_qualified_restore(self):
        with tempfile.TemporaryDirectory() as directory:
            path = self.archive(Path(directory))
            result = backup_verify.verify(path, "c" * 64)
            self.assertEqual(result["archiveIntegrity"], "passed")
            self.assertEqual(result["restoreBoot"], "not-qualified")

    def test_overlay_mutation_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = self.archive(Path(directory))
            (path / "world1" / "overlay.qcow2").write_bytes(b"tampered")
            with self.assertRaisesRegex(ValueError, "SHA256 mismatch"):
                backup_verify.verify(path, "c" * 64)

    def test_no_guest_mutation(self):
        source = (Path(__file__).parent / "backup_verify.py").read_text()
        self.assertNotIn("podman stop", source)
        self.assertNotIn("shutil.copyfile", source)


if __name__ == "__main__":
    unittest.main()
