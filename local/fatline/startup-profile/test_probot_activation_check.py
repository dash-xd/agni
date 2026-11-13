#!/usr/bin/env python3
"""Pre-activation gate regression tests using the actual activation-plan fixture."""
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

HERE = Path(__file__).resolve().parent


def load(label, filename):
    spec = importlib.util.spec_from_file_location(label, HERE / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


planner = load("activation_planner", "probot-activation-plan.py")
checker = load("activation_checker", "probot-activation-check.py")
fixtures = load("activation_fixtures", "test_probot_activation_plan.py")


class ActivationCheckTests(unittest.TestCase):
    def setup_fixture(self, root):
        setup = fixtures.ActivationPlanTests()
        migration, assessment, units, base, output, generation = setup.fixture(root)
        api_key = base / "services/credentials/logma/api-key"
        api_key.write_text("private-api-key")
        api_key.chmod(0o600)
        storage = root / "store"
        storage.mkdir()
        assessment_content = json.loads(assessment.read_text())
        for role in planner.ROLES:
            name = "a" * 32 + "-" + role
            path = storage / name / "bin"
            path.mkdir(parents=True)
            exe = path / role
            exe.write_text("legacy executable")
            assessment_content["quadlets"][role]["store_references"] = [
                "/nix/store/" + name + "/bin/" + role
            ]
        # Update assessment and migration names to reflect exact content hash.
        content = (json.dumps(assessment_content, sort_keys=True) + "\n").encode()
        digest = hashlib.sha256(content).hexdigest()
        assessment_new = assessment.with_name(digest + ".json")
        assessment.unlink()
        assessment_new.write_bytes(content)
        generation_new = digest + "-" + assessment_content["bundle"].split("/")[-1]
        migration_new = migration.with_name(generation_new)
        migration.rename(migration_new)
        output_new = output.with_name(generation_new)
        planner.prepare(migration_new, assessment_new, units, base, output_new,
                        generation_new, fixtures.BOOT, fixtures.INVOCATIONS)
        return migration_new, assessment_new, units, base, output_new, generation_new, storage

    def check(self, values, **kwargs):
        migration, assessment, units, base, output, generation, store = values
        return checker.verify(output, migration, assessment, units, base, store,
                              kwargs.get("boot_id", fixtures.BOOT),
                              kwargs.get("invocations", fixtures.INVOCATIONS),
                              generation=kwargs.get("generation", generation))

    def test_intact_generation_is_verifiable_but_not_activatable(self):
        with tempfile.TemporaryDirectory() as tmp:
            values = self.setup_fixture(Path(tmp))
            result = self.check(values)
            self.assertFalse(result["eligible"])
            self.assertIn("strict-readiness-fixtures", result["blocking"])

    def test_podman_mount_name_is_not_generation_identity(self):
        with tempfile.TemporaryDirectory() as tmp:
            values = list(self.setup_fixture(Path(tmp)))
            mounted = values[4].with_name("plan")
            values[4].rename(mounted)
            values[4] = mounted
            self.assertFalse(self.check(values)["eligible"])

    def test_snapshot_mutation_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            values = self.setup_fixture(Path(tmp))
            (values[4] / "rollback/config/config/nginx.conf").write_text("tampered")
            with self.assertRaisesRegex(ValueError, "Rollback snapshot modified"):
                self.check(values)

    def test_legacy_service_restart_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            values = self.setup_fixture(Path(tmp))
            invocations = dict(fixtures.INVOCATIONS)
            invocations["redis"] = "f" * 32
            with self.assertRaisesRegex(ValueError, "invocation changed"):
                self.check(values, invocations=invocations)

    def test_missing_legacy_store_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            values = self.setup_fixture(Path(tmp))
            (values[6] / ("a" * 32 + "-redis") / "bin/redis").unlink()
            with self.assertRaisesRegex(ValueError, "Legacy executable unavailable"):
                self.check(values)


if __name__ == "__main__":
    unittest.main()
