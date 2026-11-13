#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("agni_probot_adoption", Path(__file__).with_name("probot-adoption.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class AdoptionAssessment(unittest.TestCase):
    def fixture(self, root):
        base = root / ".local/state/nix-xd/fatline/fatline-arm-vm1"
        units = root / ".config/containers/systemd"
        (base / "credentials").mkdir(parents=True)
        (base / "config").mkdir()
        (base / "services/credentials").mkdir(parents=True)
        units.mkdir(parents=True)
        (base / "credentials/users.acl").write_text(
            "user default off\nuser publisher on >secret-redacted ~foo:* +publish\n"
            "user subscriber on >secret-redacted ~bar:* +subscribe\n")
        (base / "config/redis.conf").write_text("port 0\n")
        for role in ("redis", "nginx", "logma", "skymill"):
            (units / ("fatline-arm-vm1-" + role + ".container")).write_text(
                "[Container]\nExec=/nix/store/" + "a" * 32 + "-" + role + "/bin/service\n")
        return base, units

    def test_legacy_is_not_accepted_as_installed_profile(self):
        with tempfile.TemporaryDirectory() as temp:
            base, units = self.fixture(Path(temp))
            report = module.assess(base, units, {"redis", "nginx", "logma", "skymill"})
            self.assertEqual(report["status"], "legacy-profile-migration-required")
            self.assertFalse(report["profile_installed"])
            self.assertEqual(len(report["quadlets"]), 4)
            self.assertEqual(report["activation"], "blocked")
            self.assertNotIn("secret-redacted", json.dumps(report))
            self.assertTrue(report["prerequisites"]["preserve_publisher_subscriber"])

    def test_missing_role_and_partial_profile(self):
        with tempfile.TemporaryDirectory() as temp:
            base, units = self.fixture(Path(temp))
            (units / "fatline-arm-vm1-skymill.container").unlink()
            report = module.assess(base, units, {"redis", "nginx", "logma"})
            self.assertEqual(report["status"], "incomplete-runtime")
            self.assertEqual(report["missing_roles"], ["skymill"])
            (base / "services/profile").mkdir()
            (base / "services/profile/profile.env").write_text("profile_scope=x\n")
            with self.assertRaises(ValueError):
                module.assess(base, units, {"redis", "nginx", "logma"})

    def test_preserved_identity_required(self):
        with tempfile.TemporaryDirectory() as temp:
            base, units = self.fixture(Path(temp))
            (base / "credentials/users.acl").write_text("user default off\nuser publisher on\n")
            with self.assertRaises(ValueError):
                module.assess(base, units, {"redis", "nginx"})


if __name__ == "__main__":
    unittest.main()
