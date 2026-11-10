#!/usr/bin/env python3
import hashlib
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('renderer', HERE / 'render.py')
renderer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(renderer)


class Policy(unittest.TestCase):
    def test_runtime_secret_permissions_and_scoped_acl(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory) / 'private'
            passwords = renderer.render(root, 'fatline-arm-vm1', 16379)
            text = (root / 'users.acl').read_text()
            self.assertTrue(text.startswith('user default off\n'))
            for role, password in passwords.items():
                self.assertNotIn(password, text)
                self.assertIn('#' + hashlib.sha256(password.encode()).hexdigest(), text)
                self.assertEqual((root / role).stat().st_mode & 0o777, 0o600)
            self.assertEqual(root.stat().st_mode & 0o777, 0o700)
            self.assertEqual((root / 'users.acl').stat().st_mode & 0o777, 0o600)
            subscriber = next(line for line in text.splitlines() if line.startswith('user subscriber '))
            self.assertNotIn('+publish', subscriber)
            self.assertNotIn('~', subscriber)
            self.assertIn('&fatline-arm-vm1:qualification ', subscriber)
            self.assertNotIn('+@all', text)
            self.assertIn('port 0\n', (root / 'redis.conf').read_text())
            self.assertIn('unixsocketperm 600', (root / 'redis.conf').read_text())
            self.assertIn('proxy_pass unix:/run/redis/redis.sock;', (root / 'nginx.conf').read_text())

    def test_scope_injection_rejected(self):
        with self.assertRaises(ValueError):
            renderer.render(Path('/unused'), 'bad\nuser default on', 16379)

    def test_guest_template_keeps_proxy_out_of_credentials(self):
        source = (HERE / 'guest.sh').read_text()
        nginx = source.split('      else\n', 1)[1].split('      fi', 1)[0]
        self.assertIn('Volume=$base/socket:/run/redis:ro', nginx)
        self.assertNotIn('/run/credentials', nginx)
        self.assertIn('Network=none', source)
        self.assertIn('Internal=true', source)
        self.assertIn('Network=$scope.network', source)
        self.assertIn('--user 1001:1001', source)
        self.assertIn('--mode deny-socket', source)
        self.assertIn('NoNewPrivileges=true', source)

    def test_rootfs_operand_follows_all_container_options(self):
        import shlex
        source = (HERE / 'guest.sh').read_text().replace('\\\n', ' ')
        commands = [shlex.split(line.strip()) for line in source.splitlines()
                    if line.strip().startswith('podman run ')]
        self.assertEqual(len(commands), 2)
        for command in commands:
            rootfs = command.index('--rootfs')
            self.assertEqual(command[rootfs + 1], '$base/rootfs')
            self.assertEqual(command[rootfs + 2], '$client')
            self.assertLess(command.index('--network'), rootfs)


if __name__ == '__main__':
    unittest.main()
