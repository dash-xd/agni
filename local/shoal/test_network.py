#!/usr/bin/env python3
"""Offline contract checks for nonmutating Shoal network preflight."""
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))
import network


class NetworkTests(unittest.TestCase):
    def test_candidate_is_private_and_fail_closed(self):
        plan = json.loads((ROOT / "plan.json").read_text())
        candidate = plan["networkCandidate"]
        self.assertEqual(candidate["transport"], "qemu-socket-over-private-podman-network")
        self.assertTrue(candidate["podmanInternal"])
        self.assertEqual(candidate["egress"], "deny-by-default")
        self.assertNotEqual(candidate["farcasterIPv4"], candidate["world1IPv4"])
        self.assertEqual(set(plan["placements"]), {"farcaster", "world1"})

    def test_preflight_does_not_mutate_containers_or_guest(self):
        source = (ROOT / "network.py").read_text()
        self.assertNotIn('"podman", "--connection", machine, "run"', source)
        self.assertNotIn('"podman", "--connection", machine, "stop"', source)
        self.assertNotIn('"podman", "--connection", machine, "network", "create"', source)
        self.assertNotIn("AGNI_SHOAL_NETWORK=passed", source)
        self.assertIn("AGNI_SHOAL_NETWORK=not-assessed", source)
        self.assertIn("StrictHostKeyChecking=yes", source)

    def test_unprivileged_guest_is_valid_for_readonly_preflight(self):
        response = "arch=aarch64\nsudo=no\nnmcli=yes\nipv4=yes"
        placement = {"sshPort": 2222, "sshUser": "wisp", "sshHost": "127.0.0.1"}
        with patch.object(network, "run", return_value=response):
            observed = network.guest_preflight(placement, Path("/known_hosts"), Path("/key"))
        self.assertEqual(observed["sudo"], "no")
        self.assertEqual(observed["nmcli"], "yes")

    def test_missing_network_tools_is_rejected(self):
        response = "arch=aarch64\nsudo=no\nnmcli=no\nipv4=yes"
        placement = {"sshPort": 2222, "sshUser": "wisp", "sshHost": "127.0.0.1"}
        with patch.object(network, "run", return_value=response):
            with self.assertRaisesRegex(ValueError, "network tooling"):
                network.guest_preflight(placement, Path("/known_hosts"), Path("/key"))

    def test_mismatched_runner_is_rejected(self):
        item = [{"Id": "a" * 64, "State": {"Running": True},
                 "Config": {"Cmd": ["-netdev", "user,id=n0,hostfwd=tcp::2222-:22"]},
                 "HostConfig": {"NetworkMode": "default"}}]
        with patch.object(network, "run", return_value=json.dumps(item)):
            observed = network.inspect_runner("coreos-arm64", {"container": "vm"}, "a" * 64)
            self.assertEqual(observed["networkDevices"], ["user,id=n0,hostfwd=tcp::2222-:22"])
            with self.assertRaisesRegex(ValueError, "changed"):
                network.inspect_runner("coreos-arm64", {"container": "vm"}, "b" * 64)

    def test_second_network_device_is_rejected(self):
        item = [{"Id": "a" * 64, "State": {"Running": True},
                 "Config": {"Cmd": ["-netdev", "user,id=n0,hostfwd=tcp::2222-:22",
                                    "-netdev", "socket,id=shoal"]},
                 "HostConfig": {"NetworkMode": "default"}}]
        with patch.object(network, "run", return_value=json.dumps(item)):
            with self.assertRaisesRegex(ValueError, "Unexpected existing"):
                network.inspect_runner("coreos-arm64", {"container": "vm"}, "a" * 64)


if __name__ == "__main__":
    unittest.main()
