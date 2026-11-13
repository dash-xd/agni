#!/usr/bin/env python3
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

MODULE = Path(__file__).with_name("candidate-output.py")
spec = importlib.util.spec_from_file_location("agni_candidate_output", MODULE)
candidate_output = importlib.util.module_from_spec(spec)
spec.loader.exec_module(candidate_output)


class ImmutableCandidates(unittest.TestCase):
    def test_idempotent_and_side_by_side(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp) / "plans"
            first = candidate_output.retain_candidate(directory, {"schema": 1, "value": "a"}, "policy")
            repeated = candidate_output.retain_candidate(directory, {"value": "a", "schema": 1}, "policy")
            second = candidate_output.retain_candidate(directory, {"schema": 1, "value": "b"}, "policy")
            self.assertEqual(first, repeated)
            self.assertNotEqual(first, second)
            self.assertEqual(json.loads(first.read_text())["value"], "a")
            self.assertEqual(json.loads(second.read_text())["value"], "b")
            self.assertEqual(first.stat().st_mode & 0o777, 0o600)

    def test_existing_candidate_must_match_content(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            value = {"value": "a"}
            path = candidate_output.retain_candidate(directory, value, "guest")
            path.write_text('{"value":"unexpected"}')
            with self.assertRaises(ValueError):
                candidate_output.retain_candidate(directory, value, "guest")


if __name__ == "__main__":
    unittest.main()
