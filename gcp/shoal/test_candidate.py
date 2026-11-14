#!/usr/bin/env python3
"""Offline qualification for the existing GCP Shoal Terraform entry points."""
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent
AGNI = ROOT.parents[1]


class GCPShoalCandidateTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.contract = json.loads((ROOT / "candidate.json").read_text())

    def test_two_vm_candidate_and_eight_vm_target_are_separate(self):
        q = self.contract["qualification"]
        self.assertFalse(q["apply"])
        self.assertEqual(q["mode"], "existing-infrastructure-static-preflight")
        roles = {entry["role"]: entry for entry in q["roles"]}
        self.assertEqual(set(roles), {"farcaster", "world"})
        self.assertEqual(roles["farcaster"]["instanceCount"], 1)
        self.assertEqual(roles["world"]["instanceCount"], 1)
        self.assertEqual(roles["world"]["memberSlots"], [0])
        self.assertEqual(self.contract["productionTarget"],
                         {"farcasterCount": 1, "worldCount": 7})

    def test_provider_independent_selection(self):
        self.assertEqual(self.contract["sourcePolicy"], "exact-git-revision")
        self.assertEqual(self.contract["executionPolicy"], "runner-independent")
        for key in ("spotScheduling", "subnetOwnership", "ipv4Egress", "ipv6Egress",
                    "privateConnectivity", "fatline", "tenantIsolation"):
            self.assertIn(key, self.contract["requirements"])

    def test_existing_terraform_has_correct_proxy_output(self):
        outputs = (AGNI / "terraform/outputs.tf").read_text()
        self.assertIn("value = local.egress_proxy_ip", outputs)
        self.assertNotIn("var.egress_proxy_ip", outputs)
        leader = (AGNI / "terraform/leader/main.tf").read_text()
        members = (AGNI / "terraform/main.tf").read_text()
        self.assertIn('resource "google_compute_address" "leader"', leader)
        self.assertIn('resource "google_compute_firewall" "members_to_squid"', leader)
        self.assertIn('resource "google_compute_firewall" "leader_to_members"', members)
        self.assertIn('data "terraform_remote_state" "leader"', members)

    def test_never_assume_spot_or_cloud_apply(self):
        source = (ROOT / "candidate.json").read_text()
        self.assertNotIn("qualified", self.contract["qualification"]["mode"])
        self.assertNotIn("127.0.0.1", source)
        self.assertNotIn("coreos-arm64", source)
        self.assertNotIn("/Users/", source)


if __name__ == "__main__":
    unittest.main()
