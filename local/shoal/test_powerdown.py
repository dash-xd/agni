#!/usr/bin/env python3
"""Offline coverage for opt-in QMP and fail-closed shutdown requirements."""
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
import powerdown


class PowerdownTests(unittest.TestCase):
    def test_existing_vm_without_qmp_fails_before_inspection(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory) / "starwisp"
            folder.mkdir()
            (folder / "manifest.txt").write_text("port=2222\ncontainer_id=" + "a" * 64 + "\n")
            with patch.object(powerdown.binding, "run") as run:
                with self.assertRaisesRegex(ValueError, "QMP not enrolled"):
                    powerdown.inspect("coreos-arm64",
                        {"instance": "starwisp", "container": "coreos-starwisp"},
                        Path(directory), "farcaster")
                run.assert_not_called()

    def test_qmp_requires_pinned_loopback_port(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory) / "starwisp"
            folder.mkdir()
            (folder / "manifest.txt").write_text(
                "qmp_host_port=42222\ncontainer_id=" + "a" * 64 + "\n")
            details = [{"Id": "a" * 64, "State": {"Running": True},
                        "NetworkSettings": {"Ports": {"4444/tcp": [
                            {"HostIp": "0.0.0.0", "HostPort": "42222"}]}}}]
            with patch.object(powerdown.binding, "run", return_value=json.dumps(details)):
                with self.assertRaisesRegex(ValueError, "loopback"):
                    powerdown.inspect("coreos-arm64",
                        {"instance": "starwisp", "container": "coreos-starwisp"},
                        Path(directory), "farcaster")

    def test_acpi_request_never_forces_qemu_stop(self):
        code = (ROOT / "powerdown.py").read_text()
        self.assertIn("system_powerdown", code)
        self.assertIn("qmp_capabilities", code)
        self.assertNotIn("podman stop", code)
        self.assertNotIn("AGNI_SHOAL_BACKUP=passed", code)
        vm = (ROOT.parent / "vm/coreos-podman.sh").read_text()
        self.assertIn("COREOS_QMP_HOST_PORT", vm)
        self.assertIn('127.0.0.1:$qmp_host_port:4444', vm)
        self.assertIn("qmp_host_port", vm)


if __name__ == "__main__":
    unittest.main()
