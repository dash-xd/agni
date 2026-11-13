#!/usr/bin/env python3
"""Offline backup must reject live guests and protect backing-image provenance."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
import backup_capture


class BackupCaptureTests(unittest.TestCase):
    def test_running_container_cannot_be_backed_up(self):
        with tempfile.TemporaryDirectory() as folder:
            state = Path(folder)
            payload = [{"State": {"Running": True, "Status": "running"}, "Id": "a" * 64}]
            with patch.object(backup_capture, "call", return_value=json.dumps(payload)):
                with self.assertRaisesRegex(ValueError, "not stopped"):
                    backup_capture.inspect_stopped("coreos-arm64",
                        {"container": "coreos-starwisp", "sshPort": 2222}, state, state)

    def test_stopped_without_clean_shutdown_marker_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            state = Path(folder)
            cid = "a" * 64
            runner = "sha256:" + "b" * 64
            (state / "manifest.txt").write_text(
                "container_id=" + cid + "\nport=2222\nrunner=" + runner + "\n")
            base = state / "base.qcow2"
            base.write_bytes(b"base")
            overlay = state / "overlay.qcow2"
            overlay.write_bytes(b"overlay")
            (state / "serial.log").write_text("CoreOS running normally\n")
            (state / "build.txt").write_text("runner=" + runner +
                "\ndisk_sha256=" + backup_capture.digest(base) + "\n")
            payload = [{"State": {"Running": False, "Status": "exited"}, "Id": cid}]
            with patch.object(backup_capture, "call", return_value=json.dumps(payload)):
                with self.assertRaisesRegex(ValueError, "clean shutdown marker"):
                    backup_capture.inspect_stopped("coreos-arm64",
                        {"container": "coreos-starwisp", "sshPort": 2222}, state, state)

    def test_no_stop_or_guest_mutation(self):
        source = (ROOT / "backup_capture.py").read_text()
        self.assertNotIn("podman stop", source)
        self.assertNotIn("systemctl poweroff", source)
        self.assertIn("shutil.copyfile", source)
        self.assertIn("sha256-verified-offline-copy", source)
        self.assertNotIn("AGNI_SHOAL_NETWORK=passed", source)


if __name__ == "__main__":
    unittest.main()
