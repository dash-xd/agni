#!/usr/bin/env python3
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
def load(name, file):
    spec = importlib.util.spec_from_file_location(name, HERE / file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

verifier = load("migration_verify", "probot-migration-verify.py")
base_render = load("base_renderer", "render.py")
webhook_render = load("webhook_renderer", "probot-render.py")
HASH = "a" * 32
REV = "b" * 40
STORE = "/nix/store/" + HASH
SCOPE = "fatline-arm-vm1"


class MigrationVerificationTests(unittest.TestCase):
    def fixture(self, root):
        migration = root / "migrations" / ("c" * 64 + "-" + HASH + "-candidate")
        migration.mkdir(parents=True)
        units = root / "units"
        units.mkdir()
        store = root / "store"
        store.mkdir()
        for name in ("redis", "nginx", "probe", "node"):
            path = store / (HASH + "-" + name) / "bin"
            path.mkdir(parents=True)
            (path / {"redis": "redis-server", "nginx": "nginx", "probe": "fatline-services-probe", "node": "node"}[name]).write_text("binary")
        for name in ("logma-lifecycle", "skymill-http"):
            (store / (HASH + "-" + name)).write_text("binary")
        probot = store / (HASH + "-probot") / "router"
        probot.mkdir(parents=True)
        (probot / "serve.js").write_text("route")
        (store / (HASH + "-archive")).write_text("tar")
        (store / (HASH + "-bundle")).mkdir()
        for name in ("bootstrap.sh", "boot-wait.sh", "metadata.json"):
            (store / (HASH + "-bundle") / name).write_text("asset")
        acl = root / "users.acl"
        acl.write_text("user default off\nuser publisher on >secret\nuser subscriber on >secret\n")
        new_acl = acl.read_bytes()
        spec = {"schema": 1, "scope": SCOPE, "home": "/var/home/wisp",
                "port": 16379, "bundle": STORE + "-bundle", "archive": STORE + "-archive",
                "redis": STORE + "-redis/bin/redis-server",
                "nginx": STORE + "-nginx/bin/nginx",
                "logma": STORE + "-logma/bin/api",
                "skymill": STORE + "-skymill/bin/skymill-http",
                "probe": STORE + "-probe/bin/fatline-services-probe",
                "aclDigest": hashlib.sha256(new_acl).hexdigest()}
        source = {"schema": 1, "scenario": "probot-webhook",
                  "sources": {role: {"revision": REV} for role in ("logma", "skymill", "probot-runtime")}}
        artifacts = {"schema": 1, "system": "aarch64-linux", "ghxd_credentials_included": False,
                     "node": STORE + "-node/bin/node",
                     "artifacts": {
                         "logma": {"revision": REV, "store": STORE + "-logma-lifecycle"},
                         "skymill": {"revision": REV, "store": STORE + "-skymill-http"},
                         "probot-runtime": {"revision": REV, "store": STORE + "-probot"},
                     }}
        input_dir = migration / "input"
        input_dir.mkdir()
        for key, data in (("spec", spec), ("artifacts", artifacts), ("sources", source)):
            (input_dir / (key + ".json")).write_text(json.dumps(data))
        rendered = migration / "rendered"
        webhook_render.render(spec, artifacts, source, rendered, base_render.render)
        (rendered / "users.acl").write_bytes(new_acl)
        for role in ("logma", "skymill", "bootstrap", "probot"):
            (rendered / role).mkdir()
            (rendered / role / "redis").write_text("secret")
            (rendered / role / "redis").chmod(0o600)
        for role in ("skymill", "probot"):
            name = "http-token" if role == "skymill" else "skymill-token"
            (rendered / role / name).write_text("token")
            (rendered / role / name).chmod(0o600)
        observed = {}
        for role in verifier.ROLES[:-1]:
            f = units / (SCOPE + "-" + role + ".container")
            f.write_text("[Container]\nExec=legacy\n")
            observed[role] = {"active": True, "sha256": hashlib.sha256(f.read_bytes()).hexdigest()}
        report = {"schema": 1, "kind": "agni.probot.guest-adoption-assessment",
                  "scope": SCOPE, "status": "legacy-profile-migration-required",
                  "activation": "blocked", "profile_installed": False,
                  "bundle": STORE + "-candidate", "quadlets": observed,
                  "acl": {"sha256": hashlib.sha256(new_acl).hexdigest()}}
        # Re-key the migration to the exact assessment content digest.
        data = (json.dumps(report, indent=2) + "\n").encode()
        digest = hashlib.sha256(data).hexdigest()
        assessment = root / (digest + ".json")
        assessment.write_bytes(data)
        migration.rename(migration.with_name(digest + "-" + HASH + "-candidate"))
        return migration.with_name(digest + "-" + HASH + "-candidate"), assessment, acl, units, store

    def test_full_five_role_staged_graph(self):
        with tempfile.TemporaryDirectory() as tmp:
            candidate, assessment, acl, units, store = self.fixture(Path(tmp))
            result = verifier.verify(candidate, assessment, acl, units, store)
            self.assertEqual(result["roles"], 5)
            self.assertEqual(result["activation"], "blocked")

    def test_legacy_unit_drift_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            candidate, assessment, acl, units, store = self.fixture(Path(tmp))
            (units / (SCOPE + "-nginx.container")).write_text("changed")
            with self.assertRaisesRegex(ValueError, "Quadlet changed"):
                verifier.verify(candidate, assessment, acl, units, store)

    def test_missing_store_artifact_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            candidate, assessment, acl, units, store = self.fixture(Path(tmp))
            (store / (HASH + "-logma-lifecycle")).unlink()
            with self.assertRaisesRegex(ValueError, "Missing candidate artifact"):
                verifier.verify(candidate, assessment, acl, units, store)


if __name__ == "__main__":
    unittest.main()
