#!/usr/bin/env python3
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("agni_migration", Path(__file__).with_name("probot-migrate.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

BASE = "fatline-arm-vm1"
STORE = "/nix/store/" + "a" * 32


class MigrationSpecTests(unittest.TestCase):
    def fixture(self, root):
        units = root / "units"
        units.mkdir()
        acl = root / "users.acl"
        acl.write_text("user default off\nuser publisher on >private-acl-value ~foo:*\n"
                       "user subscriber on >private-acl-value ~bar:*\n"
                       "user logma on >hidden\nuser skymill on >hidden\n"
                       "user bootstrap off >hidden\n")
        roles = {"redis": STORE + "-redis/bin/redis-server",
                 "nginx": STORE + "-nginx/bin/nginx",
                 "logma": STORE + "-logma/bin/api",
                 "skymill": STORE + "-skymill/bin/skymill-http"}
        observed = {}
        for role, executable in roles.items():
            value = "[Container]\nExec=" + executable + "\n"
            if role == "nginx":
                value += "PublishPort=127.0.0.1:16379:6379\n"
            file = units / (BASE + "-" + role + ".container")
            file.write_text(value)
            observed[role] = {"sha256": hashlib.sha256(file.read_bytes()).hexdigest(),
                              "store_references": [executable], "active": True}
        report = {
            "schema": 1, "kind": "agni.probot.guest-adoption-assessment",
            "status": "legacy-profile-migration-required", "scope": BASE,
            "activation": "blocked", "profile_installed": False,
            "acl": {
                "sha256": hashlib.sha256(acl.read_bytes()).hexdigest(),
                "identity_line_sha256": {
                    name: hashlib.sha256(line.encode()).hexdigest()
                    for line in acl.read_text().splitlines()
                    for name in ("default", "publisher", "subscriber")
                    if line.startswith("user " + name + " ")
                }
            },
            "quadlets": observed,
            "base_credentials_present": {"logma": True, "skymill": True, "bootstrap": True},
        }
        return report, units, acl

    def resolve(self, report, units, acl, home="/var/home/wisp"):
        return module.build_spec(report, units, acl,
                                 {"probe": STORE + "-probe/bin/fatline-services-probe"},
                                 home, STORE + "-startup-profile", STORE + "-rootfs.tar")

    def test_resolves_current_guest_home_and_immutable_executables(self):
        with tempfile.TemporaryDirectory() as temp:
            report, units, acl = self.fixture(Path(temp))
            spec = self.resolve(report, units, acl)
            self.assertEqual(spec["home"], "/var/home/wisp")
            self.assertEqual(spec["redis"], STORE + "-redis/bin/redis-server")
            self.assertEqual(spec["nginx"], STORE + "-nginx/bin/nginx")
            self.assertEqual(spec["port"], 16379)
            self.assertEqual(spec["scope"], BASE)
            self.assertNotIn("private-acl-value", json.dumps(spec))

    def test_quadlet_drift_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            report, units, acl = self.fixture(Path(temp))
            (units / (BASE + "-nginx.container")).write_text("[Container]\nExec=changed\n")
            with self.assertRaisesRegex(ValueError, "Quadlet changed"):
                self.resolve(report, units, acl)

    def test_host_acl_drift_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            report, units, acl = self.fixture(Path(temp))
            acl.write_text(acl.read_text().replace("~foo:*", "~wrong:*"))
            with self.assertRaisesRegex(ValueError, "Redis ACL changed"):
                self.resolve(report, units, acl)

    def test_incomplete_quadlet_security_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for role in (*module.ROLES, "probot"):
                (root / (BASE + "-" + role + ".container")).write_text("[Container]\\n")
            (root / "profile.env").write_text("profile_scope=test\\n")
            (root / "manifest.json").write_text("{}\\n")
            with self.assertRaisesRegex(ValueError, "Missing Quadlet isolation"):
                module.validate_rendered_profile(root)

    def test_unverified_home_is_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            report, units, acl = self.fixture(Path(temp))
            with self.assertRaisesRegex(ValueError, "Unexpected rootless guest home"):
                self.resolve(report, units, acl, "/tmp/wisp")


if __name__ == "__main__":
    unittest.main()
