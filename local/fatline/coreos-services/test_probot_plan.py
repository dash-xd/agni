#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

module_spec = importlib.util.spec_from_file_location(
    "agni_probot_plan", Path(__file__).with_name("probot-plan.py"))
module = importlib.util.module_from_spec(module_spec)
module_spec.loader.exec_module(module)

HASH = "a" * 32
SHA = "b" * 40


def fixture():
    artifacts = {
        "schema": 1, "system": "aarch64-linux",
        "ghxd_credentials_included": False,
        "node": f"/nix/store/{HASH}-nodejs/bin/node",
        "artifacts": {
            name: {"revision": SHA, "store": f"/nix/store/{HASH}-{binary}"}
            for name, binary in module.NAMES.items()
        },
    }
    sources = {
        "schema": 1, "scenario": "probot-webhook",
        "sources": {name: {"revision": SHA} for name in module.ROLES},
    }
    return artifacts, sources


class ProbotGuestPlanTests(unittest.TestCase):
    def test_private_units_and_separate_secret_grants(self):
        artifact, source = fixture()
        with patch.object(Path, "is_file", return_value=True), patch.object(module.os, "access", return_value=True):
            candidate = module.plan(artifact, source, "fatline-arm-vm1")
        self.assertEqual(len(candidate["unit_templates"]), 3)
        self.assertEqual(candidate["roles"]["probot"]["redis_principal"], "probot_state")
        self.assertEqual(candidate["roles"]["skymill"]["redis_principal"], "skymill")
        self.assertEqual(candidate["roles"]["logma"]["redis_principal"], "lifecycle_subscribe")
        self.assertIn("github-app-key", candidate["roles"]["probot"]["credentials"])
        self.assertNotIn("token.sops.json", str(candidate))
        for unit in candidate["unit_templates"].values():
            self.assertIn("ReadOnly=true", unit)
            self.assertIn("Volume=/var/mnt/nixstore:/nix/store:ro", unit)
            self.assertNotIn("PublishPort=", unit)
        self.assertIn("blocked-until", candidate["activation"])

    def test_mismatched_revision_denied(self):
        artifact, source = fixture()
        artifact["artifacts"]["logma"]["revision"] = "c" * 40
        with self.assertRaises(ValueError):
            module.validate(artifact, source)

    def test_github_oauth_credential_is_not_application_authority(self):
        artifact, source = fixture()
        artifact["ghxd_credentials_included"] = True
        with self.assertRaises(ValueError):
            module.validate(artifact, source)


if __name__ == "__main__":
    unittest.main()
