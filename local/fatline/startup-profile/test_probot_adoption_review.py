#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("adoption_review", Path(__file__).with_name("probot-adoption-review.py"))
review = importlib.util.module_from_spec(spec)
spec.loader.exec_module(review)

STORE = "/nix/store/" + "a" * 32


class AdoptionReviewTests(unittest.TestCase):
    def fixture(self):
        return {
            "schema": 1,
            "kind": "agni.probot.guest-adoption-assessment",
            "scope": "fatline-arm-vm1",
            "activation": "blocked",
            "bundle": STORE + "-candidate",
            "status": "legacy-profile-migration-required",
            "profile_installed": False,
            "acl": {"sha256": "b" * 64, "identity_line_sha256": {
                "default": "a" * 64, "publisher": "a" * 64, "subscriber": "a" * 64,
            }},
            "quadlets": {
                role: {"active": True, "store_references": [STORE + "-legacy-" + role]}
                for role in ("redis", "nginx", "logma", "skymill")
            },
            "base_credentials_present": {"logma": True, "skymill": True, "bootstrap": False},
        }

    def bundle(self):
        return {"bundle": STORE + "-candidate", "artifacts": {
            "skymill": {"path": STORE + "-skymill-http"},
            "logma": {"path": STORE + "-logma-lifecycle"},
            "probot-runtime": {"path": STORE + "-probot"},
            "node": {"path": STORE + "-node/bin/node"},
        }}

    def test_legacy_plan_does_not_activate(self):
        result = review.review(self.fixture(), self.bundle())
        self.assertEqual(result["next_boundary"], "qualify-controlled-profile-migration")
        self.assertEqual(result["activation"], "blocked")
        self.assertFalse(result["selected_components"]["logma"]["already_selected"])
        self.assertFalse(result["existing_roles"]["probot"]["present"])
        self.assertFalse(result["base_credentials_present"]["bootstrap"])

    def test_wrong_bundle_fails_closed(self):
        report = self.fixture()
        report["bundle"] = STORE + "-different"
        with self.assertRaises(ValueError):
            review.review(report, self.bundle())

    def test_missing_host_identity_fails_closed(self):
        report = self.fixture()
        report["acl"]["identity_line_sha256"].pop("publisher")
        with self.assertRaises(ValueError):
            review.review(report, self.bundle())


if __name__ == "__main__":
    unittest.main()
