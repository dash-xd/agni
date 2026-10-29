#!/usr/bin/env python3
import hashlib
import json
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RENDER = ROOT / "scripts" / "render-users-acl.py"
POLICY = ROOT / "acl-policy.json"


class RenderACLTest(unittest.TestCase):
    def test_scoped_rules_hashed_credentials_and_digest(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            secrets = root / "credentials"
            secrets.mkdir(mode=0o700)
            passwords = {name: f"qualification-{name}-" + "x" * 40 for name in ("logma", "skymill", "bootstrap")}
            for name, password in passwords.items():
                (secrets / name).write_text(password + "\n", encoding="utf-8")
            output = root / "users.acl"
            run = subprocess.run(["python3", str(RENDER), str(POLICY), str(secrets), str(output)], check=True, capture_output=True, text=True)
            acl = output.read_text(encoding="utf-8")
            self.assertIn("user default off", acl)
            self.assertIn("~fatline-prod:logma:*", acl)
            self.assertIn("&fatline-prod:*", acl)
            self.assertIn("~fatline-prod:skymill:stream:github.webhooks", acl)
            self.assertIn("~fatline-prod:skymill:idempotency:ZmF0bGluZS1wcm9kOnNreW1pbGw6c3RyZWFtOmdpdGh1Yi53ZWJob29rcw:*", acl)
            self.assertIn("+function|load +function|list +acl|setuser", acl)
            self.assertNotIn("+@all", acl)
            self.assertNotIn("~*", acl)
            for name, password in passwords.items():
                digest = hashlib.sha256(password.encode()).hexdigest()
                self.assertIn("user " + name + " on #" + digest, acl)
                self.assertNotIn(password, acl)
            evidence = json.loads(Path(str(output) + ".evidence.json").read_text(encoding="utf-8"))
            self.assertEqual(evidence["policySha256"], hashlib.sha256(POLICY.read_bytes()).hexdigest())
            self.assertEqual(run.stdout.strip(), evidence["policySha256"])
            self.assertEqual(output.stat().st_mode & 0o777, 0o644)

    def test_missing_credentials_fail_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            secrets = root / "credentials"
            secrets.mkdir()
            for name in ("logma", "skymill"):
                (secrets / name).write_text("x" * 40, encoding="utf-8")
            result = subprocess.run(["python3", str(RENDER), str(POLICY), str(secrets), str(root / "users.acl")], capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((root / "users.acl").exists())


if __name__ == "__main__":
    unittest.main()
