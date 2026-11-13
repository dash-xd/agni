#!/usr/bin/env python3
"""Fail-closed offline tests for the Agni-owned 9P storage gate."""
import importlib.util
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
spec = importlib.util.spec_from_file_location("shoal_storage", ROOT / "storage.py")
storage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(storage)


class StorageTests(unittest.TestCase):
    def test_guest_script_requires_ro_9p_rootless_and_two_readers(self):
        script = storage.GUEST_PROBE
        for expected in ("FSTYPE --mountpoint", "= 9p", "*,ro,*",
                         "Rootless", "--network none", "--cap-drop all",
                         "--read-only", "for n in a b", "dst=/nix/store,ro",
                         "SHOAL_EXPECTED_BUSYBOX_SHA256", "boot=$boot"):
            self.assertIn(expected, script)

    def test_network_and_services_never_promoted_by_storage(self):
        for excluded in ("AGNI_SHOAL_NETWORK=passed", "AGNI_SHOAL_SERVICES=passed",
                         "AGNI_SHOAL_GUEST_LOCAL_STORE=passed"):
            self.assertNotIn(excluded, storage.GUEST_PROBE)

    def test_invalid_stage_fails_before_live_binding(self):
        with patch.object(storage.binding, "bind") as bind:
            with self.assertRaisesRegex(ValueError, "Only one Farcaster"):
                storage.qualify("world7")
            bind.assert_not_called()

    def test_staging_revision_must_match_host_checkout(self):
        with patch.object(storage, "run", side_effect=["a" * 40, "b" * 40]):
            with patch.dict("os.environ", {"NIX_XD_RUNTIME_REPO": str(ROOT.parent.parent)}):
                with self.assertRaisesRegex(ValueError, "Stage the selected"):
                    storage.staged_flake(["podman", "exec", "nix-xd-arm"])


if __name__ == "__main__":
    unittest.main()
