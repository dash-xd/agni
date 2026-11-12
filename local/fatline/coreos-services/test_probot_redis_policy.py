#!/usr/bin/env python3
import importlib.util
import json
import os
from pathlib import Path
import unittest

planner = os.environ.get("AGNI_PROBOT_REDIS_PLANNER")
baseline = os.environ.get("AGNI_PROBOT_REDIS_BASELINE")
if not planner or not baseline:
    raise SystemExit("Pinned Redis policy inputs required")
spec = importlib.util.spec_from_file_location("probot_redis_policy", planner)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

def source_fixture():
    return {"schema": 1, "scenario": "probot-webhook",
            "sources": {name: {"revision": "a" * 40}
                        for name in ("logma", "skymill", "probot-runtime")}}

class PolicyTest(unittest.TestCase):
    def test_scoped_roles_and_hashed_stream(self):
        base = json.loads(Path(baseline).read_text())
        result = module.build_policy(base, source_fixture(), "fatline-arm-vm1")
        self.assertEqual(set(result["users"]), module.ROLES)
        prefix = result["users"]["skymill"]["keys"][0]
        self.assertRegex(prefix, r"^skymill:\{[0-9a-f]{32}\}:\*$")
        self.assertEqual(result["users"]["lifecycle_publish"]["commands"][-1], "publish")
        self.assertNotIn("publish", result["users"]["lifecycle_subscribe"]["commands"])
        self.assertEqual(result["componentRevisions"]["skymill"], "a" * 40)
        for role in result["users"].values():
            self.assertNotIn("+@all", str(role))
            self.assertNotIn("~*", str(role))

    def test_missing_component_fails(self):
        base = json.loads(Path(baseline).read_text())
        source = source_fixture()
        del source["sources"]["logma"]
        with self.assertRaises(ValueError):
            module.build_policy(base, source, "fatline-arm-vm1")

if __name__ == "__main__":
    unittest.main()
