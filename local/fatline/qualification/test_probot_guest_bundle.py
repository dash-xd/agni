#!/usr/bin/env python3
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

path = Path(__file__).with_name("probot-guest-bundle.py")
spec = importlib.util.spec_from_file_location("agni_probot_bundle", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

SHA = "a" * 40
STORE = "/nix/store/" + "b" * 32
SOURCE = {role: {"revision": SHA} for role in ("logma", "skymill", "probot-runtime")}


class BundleTests(unittest.TestCase):
    def fixture(self, root):
        fixtures = {
            "artifacts": {
                "schema": 1, "system": "aarch64-linux",
                "ghxd_credentials_included": False,
                "node": STORE + "-node/bin/node",
                "artifacts": {
                    "logma": {"revision": SHA, "store": STORE + "-logma-lifecycle"},
                    "skymill": {"revision": SHA, "store": STORE + "-skymill-http"},
                    "probot-runtime": {"revision": SHA, "store": STORE + "-probot"},
                },
            },
            "sources": {"schema": 1, "scenario": "probot-webhook", "sources": SOURCE},
            "policy": {"schema": 1, "scope": "fatline-arm-vm1",
                       "users": {k: {} for k in (
                           "logma", "skymill", "bootstrap", "probot_state",
                           "lifecycle_publish", "lifecycle_subscribe")}},
            "plan": {
                "schema": 1, "scope": "fatline-arm-vm1",
                "source_revisions": {k: SHA for k in SOURCE},
                "activation": "blocked-until-role-env-redis-acl-and-github-app-secrets-bound",
            },
        }
        paths = {}
        for name, value in fixtures.items():
            file = root / (name + ".json")
            file.write_text(json.dumps(value))
            paths[name] = file
        return paths

    def test_nonsecret_bundle_and_rejection_of_replacement(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            files = self.fixture(root)
            dest = root / "bundle"
            module.assemble(files["artifacts"], files["sources"],
                            files["policy"], files["plan"], dest)
            sums = (dest / "SHA256SUMS").read_text().splitlines()
            self.assertEqual(len(sums), 5)
            for row in sums:
                digest, name = row.split("  ")
                self.assertEqual(hashlib.sha256((dest / name).read_bytes()).hexdigest(), digest)
            self.assertEqual(len((dest / "artifacts.tsv").read_text().splitlines()), 4)
            with self.assertRaises(ValueError):
                module.assemble(files["artifacts"], files["sources"],
                                files["policy"], files["plan"], dest)

    def test_fails_on_wrong_source_revision(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            files = self.fixture(root)
            bad = json.loads(files["sources"].read_text())
            bad["sources"]["skymill"]["revision"] = "c" * 40
            files["sources"].write_text(json.dumps(bad))
            with self.assertRaises(ValueError):
                module.assemble(files["artifacts"], files["sources"],
                                files["policy"], files["plan"], root / "invalid")


if __name__ == "__main__":
    unittest.main()
