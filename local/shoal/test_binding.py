#!/usr/bin/env python3
"""Offline regression tests for the single-world binding contract."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("shoal_binding", ROOT / "binding.py")
binding = importlib.util.module_from_spec(spec)
spec.loader.exec_module(binding)


class BindingTests(unittest.TestCase):
    def test_plan_has_only_two_distinct_guests(self):
        plan = json.loads((ROOT / "plan.json").read_text())
        self.assertEqual(set(plan["placements"]), {"farcaster", "world1"})
        self.assertNotEqual(plan["placements"]["farcaster"]["sshPort"],
                            plan["placements"]["world1"]["sshPort"])
        self.assertNotEqual(plan["placements"]["farcaster"]["container"],
                            plan["placements"]["world1"]["container"])
        self.assertEqual(plan["gates"]["network"], "unqualified")

    def test_runner_must_publish_exact_loopback_port(self):
        valid = [{
            "Id": "a" * 64, "State": {"Running": True},
            "NetworkSettings": {"Ports": {
                "2222/tcp": [{"HostIp": "127.0.0.1", "HostPort": "2222"}]
            }},
        }]
        with patch.object(binding, "run", return_value=json.dumps(valid)):
            self.assertEqual(binding.inspect_binding("coreos-arm64", "coreos-starwisp", 2222),
                             "a" * 64)
            with self.assertRaisesRegex(ValueError, "does not publish"):
                binding.inspect_binding("coreos-arm64", "coreos-starwisp", 2223)
        valid[0]["State"]["Running"] = False
        with patch.object(binding, "run", return_value=json.dumps(valid)):
            with self.assertRaisesRegex(ValueError, "not the expected running"):
                binding.inspect_binding("coreos-arm64", "coreos-starwisp", 2222)

    def test_stage_selection_fails_closed(self):
        with self.assertRaisesRegex(ValueError, "Select farcaster or world1"):
            binding.bind("world7")

    def test_missing_source_pin_fails_before_accessing_guests(self):
        with patch.dict("os.environ", {"NIX_XD_SELECTED_PROJECT_REV": ""}):
            with self.assertRaisesRegex(ValueError, "Exact selected Agni"):
                binding.bind("farcaster")

    def test_without_live_vm_cannot_claim_binding(self):
        with tempfile.TemporaryDirectory() as tmp:
            with patch.dict("os.environ", {
                "NIX_XD_SELECTED_PROJECT_REV": "a" * 40,
                "SHOAL_RECEIPT_ROOT": tmp,
            }):
                with patch.object(binding, "run", return_value="b" * 40):
                    with self.assertRaisesRegex(ValueError, "Selected Agni source moved"):
                        binding.bind("farcaster")
            self.assertFalse(list(Path(tmp).iterdir()))


if __name__ == "__main__":
    unittest.main()
