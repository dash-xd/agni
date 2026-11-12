#!/usr/bin/env python3
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


stage = load("agni_stage_test", os.environ["AGNI_PROBOT_STAGE"])
profile_tests = load("agni_profile_fixture", os.environ["AGNI_PROBOT_PROFILE_RENDER_TEST"])
credential_tests = load("agni_credential_fixture", os.environ["AGNI_PROBOT_CREDENTIAL_GENERATOR_TEST"])


class StageCandidate(unittest.TestCase):
    def test_complete_candidate_and_non_mutating_staging(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            spec, artifacts, sources = profile_tests.fixture()
            old_acl, prior, policy = credential_tests.CredentialGeneration().fixture(root)
            paths = {}
            for name, value in (("spec", spec), ("artifacts", artifacts), ("sources", sources)):
                path = root / (name + ".json")
                path.write_text(json.dumps(value))
                paths[name] = path
            old_acl_bytes = old_acl.read_bytes()
            out = root / "incoming"
            stage.stage(paths["spec"], paths["artifacts"], paths["sources"], policy,
                        old_acl, prior, out,
                        Path(os.environ["AGNI_PROBOT_REDIS_RENDERER"]),
                        Path(os.environ["AGNI_PROBOT_CREDENTIAL_GENERATOR"]),
                        Path(os.environ["AGNI_PROBOT_PROFILE_RENDERER"]),
                        Path(os.environ["AGNI_PROBOT_STARTUP_RENDERER"]))
            self.assertEqual(len(list(out.glob("*.container"))), 5)
            self.assertEqual(old_acl.read_bytes(), old_acl_bytes)
            self.assertFalse((out / ".generation").exists())
            self.assertEqual((out / "skymill/http-token").read_bytes(),
                             (out / "probot/skymill-token").read_bytes())
            self.assertEqual((out / "skymill/http-token").stat().st_mode & 0o777, 0o600)
            self.assertTrue((out / "users.acl").is_file())
            self.assertTrue((out / "profile.env").is_file())
            with self.assertRaises(ValueError):
                stage.stage(paths["spec"], paths["artifacts"], paths["sources"], policy,
                            old_acl, prior, out,
                            Path(os.environ["AGNI_PROBOT_REDIS_RENDERER"]),
                            Path(os.environ["AGNI_PROBOT_CREDENTIAL_GENERATOR"]),
                            Path(os.environ["AGNI_PROBOT_PROFILE_RENDERER"]),
                            Path(os.environ["AGNI_PROBOT_STARTUP_RENDERER"]))


if __name__ == "__main__":
    unittest.main()
