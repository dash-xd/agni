#!/usr/bin/env python3
"""Static fail-closed qualification of rendered independent processor Quadlets."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("render_subscription_units", ROOT / "render-subscription-units.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

GOOD = {
    "schema": 1,
    "scope": "fatline-arm-vm1",
    "subscription_revision": "1788ee94235b83f2b6229b95acbc98469f3eaf85",
    "skymill_binary": "/nix/store/" + "a" * 32 + "-skymill-http",
    "node_binary": "/nix/store/" + "b" * 32 + "-nodejs/bin/node",
    "probot_root": "/nix/store/" + "c" * 32 + "-probot",
    "runtime_root": "/home/wisp/.local/state/nix-xd/fatline/fatline-arm-vm1/services",
}


class Qualification(unittest.TestCase):
    def render(self, config=GOOD):
        d = tempfile.TemporaryDirectory()
        self.addCleanup(d.cleanup)
        target = Path(d.name) / "units"
        module.render(config, target)
        return {p.name: p.read_text() for p in target.iterdir()}

    def test_two_isolated_service_pairs(self):
        entries = self.render()
        self.assertEqual(len(entries), 5)
        self.assertEqual(json.loads(entries["manifest.json"])["activation"], "blocked")
        for group in ("a", "b"):
            prefix = "fatline-arm-vm1-subscription-" + group
            transport = entries[prefix + "-skymill.container"]
            processor = entries[prefix + "-processor.container"]
            self.assertIn("Requires=fatline-arm-vm1-redis.service fatline-arm-vm1-nginx.service", transport)
            self.assertIn("Requires=" + prefix + "-skymill.service fatline-arm-vm1-redis.service", processor)
            self.assertIn("BindsTo=" + prefix + "-skymill.service", processor)
            self.assertIn("Wants=fatline-arm-vm1-logma.service", processor)
            self.assertIn("Restart=on-failure", processor)
            self.assertIn("Environment=PROBOT_RUNTIME_WORKER_ENABLED=false", processor)
            self.assertNotIn("[Install]", processor)
            self.assertNotIn("[Install]", transport)
            self.assertIn("ConditionPathExists=/run/agni/unqualified-subscription-activation", processor)
            self.assertIn("ConditionPathExists=/run/agni/unqualified-subscription-activation", transport)
            self.assertIn("Volume=" + GOOD["runtime_root"] + "/credentials/" + group + "/probot:/run/credentials:ro", processor)
            self.assertIn("Volume=" + GOOD["runtime_root"] + "/credentials/" + group + "/skymill:/run/credentials:ro", transport)
        self.assertNotEqual(entries["fatline-arm-vm1-subscription-a-processor.container"],
                            entries["fatline-arm-vm1-subscription-b-processor.container"])

    def test_invalid_scope_and_source_fail_closed(self):
        for attr, invalid in [
            ("schema", 2), ("scope", "production"), ("subscription_revision", "0" * 40),
            ("skymill_binary", "/usr/bin/skymill"), ("node_binary", "/usr/bin/node"),
            ("probot_root", "/tmp/probot"), ("runtime_root", "/tmp/../tmp"),
        ]:
            with self.subTest(attr=attr), self.assertRaises(ValueError):
                self.render({**GOOD, attr: invalid})

    def test_no_baseline_unit_collision_or_inline_secret(self):
        entries = self.render()
        for name, content in entries.items():
            if not name.endswith(".container"):
                continue
            self.assertNotIn("fatline-arm-vm1-probot.container", name)
            self.assertNotIn("fatline-arm-vm1-skymill.container", name)
            self.assertNotIn("Password=", content)
            self.assertNotIn("Environment=REDIS_PASSWORD=", content)
            self.assertIn("ReadOnly=true", content)
            self.assertIn("DropCapability=all", content)
            self.assertIn("NoNewPrivileges=true", content)


if __name__ == "__main__":
    unittest.main(verbosity=2)
