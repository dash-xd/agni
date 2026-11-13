#!/usr/bin/env python3
"""Regression fixtures for isolated rollback materialization."""
import importlib.util
from pathlib import Path
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, HERE / filename)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result

fixtures = module("recovery_fixtures", "test_probot_activation_check.py")
recovery = module("recovery_qualifier", "probot-recovery-qualify.py")


class RecoveryTests(unittest.TestCase):
    def setup(self, root):
        values = fixtures.ActivationCheckTests().setup_fixture(root)
        _, _, units, _, plan, generation, _ = values
        for role in ("nginx", "logma", "skymill"):
            name = fixtures.fixtures.SCOPE + "-" + role + ".container"
            original = units / name
            dependencies = "Requires=" + fixtures.fixtures.SCOPE + "-redis.service\nAfter=" + fixtures.fixtures.SCOPE + "-redis.service\n"
            if role == "logma":
                dependencies += "Requires=" + fixtures.fixtures.SCOPE + "-nginx.service\nAfter=" + fixtures.fixtures.SCOPE + "-nginx.service\n"
            original.write_text("[Unit]\n" + dependencies + "[Container]\nExec=" + role + "\n")
            # Adjust both recorded rollback SHA and copied snapshot to reproduce
            # a qualified four-role graph without changing the real VM state.
            import hashlib
            import json
            checksum = hashlib.sha256(original.read_bytes()).hexdigest()
            plan_data = json.loads((plan / "plan.json").read_text())
            plan_data["rollback_checksums"]["quadlets"][name] = checksum
            (plan / "plan.json").write_text(json.dumps(plan_data))
            (plan / "rollback/quadlets" / name).write_bytes(original.read_bytes())
        return values

    def test_restore_four_role_graph_without_live_mutation(self):
        with tempfile.TemporaryDirectory() as directory:
            values = self.setup(Path(directory))
            units = values[2]
            baseline = {f.name: f.read_bytes() for f in units.iterdir()}
            destination = Path(directory) / "recovery"
            result = recovery.recover(values[4], destination, values[5])
            self.assertEqual(result["roles"], 4)
            self.assertNotEqual(destination.resolve(), units.resolve())
            self.assertEqual(baseline, {f.name: f.read_bytes() for f in units.iterdir()})
            self.assertEqual((destination / "quadlets" / (fixtures.fixtures.SCOPE + "-redis.container")).read_bytes(),
                             baseline[fixtures.fixtures.SCOPE + "-redis.container"])

    def test_tampered_snapshot_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            values = self.setup(Path(directory))
            item = values[4] / "rollback/credentials/logma/redis"
            item.write_text("tamper")
            with self.assertRaisesRegex(ValueError, "integrity mismatch"):
                recovery.recover(values[4], Path(directory) / "recovery", values[5])

    def test_wrong_generation_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            values = self.setup(Path(directory))
            with self.assertRaisesRegex(ValueError, "generation mismatch"):
                recovery.recover(values[4], Path(directory) / "recovery", "f" * 64 + "-" + "a" * 32 + "-candidate")

    def test_rollback_does_not_override_existing_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            values = self.setup(Path(directory))
            destination = Path(directory) / "recovery"
            destination.mkdir()
            with self.assertRaisesRegex(ValueError, "must not exist"):
                recovery.recover(values[4], destination, values[5])


if __name__ == "__main__":
    unittest.main()
