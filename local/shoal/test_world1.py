#!/usr/bin/env python3
"""Offline checks for isolated World 1 profile and first-boot host key lifecycle."""
import importlib.util
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))

def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

world1 = load("world1")
hostkey = load("hostkey")


class World1Tests(unittest.TestCase):
    def test_profile_ignition_and_hardware_boundaries(self):
        source = (ROOT.parent.parent / "qemu/coreos-live/local/flake.nix").read_text()
        adapter = (ROOT.parent / "vm/coreos-podman.sh").read_text()
        profile = (ROOT.parent.parent / "qemu/coreos-live/profiles/shoal-world1/butane/world1-9p.bu").read_text()
        plan = json.loads((ROOT / "plan.json").read_text())
        self.assertEqual(set(plan["placements"]), {"farcaster", "world1"})
        self.assertEqual(plan["placements"]["world1"]["sshPort"], 2223)
        self.assertIn("ignitionShoalWorld1_9p", source)
        self.assertIn("COREOS_WORLD1_BUTANE", adapter)
        self.assertIn('World 1 must inherit the immutable Farcaster base artifacts', adapter)
        self.assertIn('Independent guest requires its own Ignition', adapter)
        self.assertIn("inline: shoal-world1", profile)
        self.assertIn("What=nixstore", profile)
        self.assertIn("ro,nofail,nodev,nosuid", profile)
        self.assertNotIn("logmash.service", profile)

    def test_world1_selects_plan_identity_and_unchanged_base(self):
        with tempfile.TemporaryDirectory() as tmp:
            farcaster = Path(tmp) / "starwisp"
            farcaster.mkdir()
            (farcaster / "build.txt").write_text("shared_nix_volume=nix-xd-arm-store\n")
            (farcaster / "base.qcow2").touch()
            env = {"SHOAL_STATE_ROOT": tmp, "NIX_XD_SELECTED_PROJECT_REV": "a" * 40, "NIX_XD_PROJECT": "agni20261113.0"}
            with patch.dict(os.environ, env), \
                 patch.object(world1.binding, "run", return_value="a" * 40), \
                 patch.object(world1.subprocess, "run") as run:
                world1.execute("ignition")
                arguments, opts = run.call_args
                self.assertEqual(arguments[0][-1], "ignition")
                selected = opts["env"]
                self.assertEqual(selected["COREOS_PROFILE"], "shoal-world1")
                self.assertEqual(selected["COREOS_FLAKE"], "/workspaces/agni20261113.0/qemu/coreos-live/local")
                self.assertEqual(selected["COREOS_SSH_PORT"], "2223")
                self.assertEqual(selected["COREOS_CONTAINER_NAME"], "coreos-shoal-world1")
                self.assertEqual(selected["COREOS_ARTIFACT_STATE"], str(farcaster.resolve()))
                self.assertEqual(selected["COREOS_NIX_STORE_VOLUME"], "nix-xd-arm-store")

    def test_missing_base_refuses_to_start(self):
        with tempfile.TemporaryDirectory() as tmp:
            with patch.dict(os.environ, {"SHOAL_STATE_ROOT": tmp,
                                          "NIX_XD_SELECTED_PROJECT_REV": "a" * 40, "NIX_XD_PROJECT": "agni20261113.0"}), \
                 patch.object(world1.binding, "run", return_value="a" * 40), \
                 patch.object(world1.subprocess, "run") as run:
                with self.assertRaisesRegex(ValueError, "base artifacts are missing"):
                    world1.execute("start")
                run.assert_not_called()

    def test_enrollment_requires_explicit_pinned_fingerprint(self):
        with tempfile.TemporaryDirectory() as tmp:
            state = Path(tmp) / "shoal-world1"
            state.mkdir()
            cid = "a" * 64
            (state / "manifest.txt").write_text(f"container_id={cid}\n")
            fingerprint = "SHA256:fixtureKey"
            env = {"SHOAL_STATE_ROOT": tmp, "NIX_XD_SELECTED_PROJECT_REV": "b" * 40}
            with patch.dict(os.environ, env), \
                 patch.object(hostkey.binding, "run", return_value="b" * 40), \
                 patch.object(hostkey, "collect", return_value=(cid, "[127.0.0.1]:2223 ssh-ed25519 AAAA\n", fingerprint)):
                hostkey.execute("plan")
                self.assertFalse((state / "known_hosts").exists())
                with self.assertRaisesRegex(ValueError, "Explicit fingerprint confirmation"):
                    hostkey.execute("enroll")
                self.assertFalse((state / "known_hosts").exists())
                with patch.dict(os.environ, {"SHOAL_WORLD1_HOSTKEY_CONFIRM": fingerprint}):
                    hostkey.execute("enroll")
                self.assertTrue((state / "known_hosts").exists())
                hostkey.execute("plan")
                self.assertIn("[127.0.0.1]:2223", (state / "known_hosts").read_text())


if __name__ == "__main__":
    unittest.main()
