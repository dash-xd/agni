#!/usr/bin/env python3
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

MODULE = Path(__file__).with_name("probot-activation-plan.py")
spec = importlib.util.spec_from_file_location("agni_activation_plan_test", MODULE)
planner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(planner)

SCOPE = "fatline-arm-vm1"
BUNDLE = "/nix/store/" + "a" * 32 + "-candidate"
INVOCATIONS = {role: "b" * 32 for role in planner.ROLES}
BOOT = "11111111-2222-3333-4444-555555555555"


class ActivationPlanTests(unittest.TestCase):
    def fixture(self, root):
        base = root / "base"
        units = root / "units"
        units.mkdir()
        for filename, value in (("credentials/users.acl", "user default off\nuser publisher on >secret\nuser subscriber on >secret\n"),
                                ("config/redis.conf", "save \"\"\nappendonly no\n"),
                                ("config/nginx.conf", "events {}\n"),
                                ("services/bootstrap-template.acl", "user default off\n"),
                                ("services/boot-wait.sh", "#!/bin/sh\n")):
            item = base / filename
            item.parent.mkdir(parents=True, exist_ok=True)
            item.write_text(value)
        for role in ("logma", "skymill", "bootstrap"):
            file = base / "services" / "credentials" / role / "redis"
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text("secret-value-" + role)
        rows = {}
        for role in planner.ROLES:
            name = SCOPE + "-" + role + ".container"
            item = units / name
            item.write_text("[Container]\nExec=" + role + "\n")
            rows[role] = {"sha256": hashlib.sha256(item.read_bytes()).hexdigest()}
        (units / (SCOPE + ".network")).write_text("[Network]\nInternal=true\n")
        assessment = {
            "scope": SCOPE, "status": "legacy-profile-migration-required",
            "activation": "blocked", "bundle": BUNDLE,
            "quadlets": rows,
            "acl": {"sha256": hashlib.sha256((base / "credentials/users.acl").read_bytes()).hexdigest()}
        }
        evidence_bytes = (json.dumps(assessment, sort_keys=True) + "\n").encode()
        digest = hashlib.sha256(evidence_bytes).hexdigest()
        evidence = root / (digest + ".json")
        evidence.write_bytes(evidence_bytes)
        generation = digest + "-" + BUNDLE.split("/")[-1]
        migration = root / "migrations" / generation
        rendered = migration / "rendered"
        rendered.mkdir(parents=True)
        (rendered / "users.acl").write_text("private staged acl")
        (rendered / "profile.env").write_text("profile_roles='redis nginx logma skymill probot'\n")
        (rendered / "manifest.json").write_text(json.dumps({
            "aclDigest": hashlib.sha256((rendered / "users.acl").read_bytes()).hexdigest()
        }))
        output = root / "plans" / generation
        return migration, evidence, units, base, output, generation

    def call(self, paths):
        migration, evidence, units, base, output, generation = paths
        return planner.prepare(migration, evidence, units, base, output, generation, BOOT, INVOCATIONS)

    def test_private_rollback_snapshot_does_not_mutate_running_inputs(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = self.fixture(Path(directory))
            old = (paths[3] / "credentials/users.acl").read_bytes()
            plan = self.call(paths)
            self.assertFalse(plan["activation"]["allowed"])
            self.assertFalse(plan["rollback"]["executed"])
            self.assertTrue(plan["data_loss"]["restart_loses_ram_only_streams"])
            self.assertEqual(plan["rollback"]["legacy_store_roots"], "must-remain-pinned-by-store-owner-through-rollback-window")
            self.assertEqual(old, (paths[3] / "credentials/users.acl").read_bytes())
            self.assertEqual(old, (paths[4] / "rollback/config/credentials/users.acl").read_bytes())
            self.assertEqual((paths[4] / "plan.json").stat().st_mode & 0o777, 0o600)
            self.assertEqual((paths[4] / "rollback/credentials/logma/redis").stat().st_mode & 0o777, 0o600)
            self.assertNotIn("secret-value", (paths[4] / "plan.json").read_text())

    def test_repeat_does_not_overwrite_private_snapshot(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = self.fixture(Path(directory))
            self.call(paths)
            with self.assertRaisesRegex(ValueError, "already exists"):
                self.call(paths)

    def test_legacy_drift_blocks_preparation(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = self.fixture(Path(directory))
            (paths[2] / (SCOPE + "-redis.container")).write_text("modified")
            with self.assertRaisesRegex(ValueError, "Quadlet changed"):
                self.call(paths)
            self.assertFalse(paths[4].exists())

    def test_wrong_generation_blocks_preparation(self):
        with tempfile.TemporaryDirectory() as directory:
            paths = list(self.fixture(Path(directory)))
            paths[5] = "f" * 64 + "-" + "a" * 32 + "-candidate"
            with self.assertRaisesRegex(ValueError, "Unexpected staged generation"):
                self.call(paths)


if __name__ == "__main__":
    unittest.main()
