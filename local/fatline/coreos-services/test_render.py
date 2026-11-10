import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('services_renderer', HERE / 'render.py')
renderer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(renderer)

class RuntimePolicy(unittest.TestCase):
    def test_scoped_roles_preserve_existing_reader_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            original = root / 'original'; original.mkdir()
            old = 'user default off\nuser publisher on #fixture -@all &scope:qualification +publish\nuser subscriber on #reader -@all &scope:qualification +subscribe\n'
            (original / 'users.acl').write_text(old)
            bundle = root / 'bundle'; bundle.mkdir()
            for name, source in [('acl-policy.json', HERE.parent/'acl-policy.json'), ('render-users-acl.py', HERE.parent/'scripts/render-users-acl.py')]:
                (bundle/name).write_bytes(source.read_bytes())
            out = root / 'generated'
            renderer.render(bundle, original, out, 'scope')
            acl = (out/'users.acl').read_text()
            self.assertIn('user subscriber on #reader', acl)
            self.assertIn('~scope:logma:lifecycle:*', acl)
            self.assertIn('~scope:skymill:stream:github.webhooks', acl)
            self.assertNotIn('~fatline-prod:', acl)
            for role in ('logma','skymill','bootstrap'):
                secret = (out/role/'redis').read_text().strip()
                self.assertNotIn(secret, acl)
                self.assertIn(hashlib.sha256(secret.encode()).hexdigest(), acl)
                self.assertEqual((out/role).stat().st_mode & 0o777, 0o700)
                self.assertEqual((out/role/'redis').stat().st_mode & 0o777, 0o600)
            self.assertEqual((out/'users.acl').stat().st_mode & 0o777, 0o600)
            with self.assertRaises(ValueError): renderer.render(bundle, original, out, 'scope')

    def test_transport_matches_both_logma_redis_clients(self):
        script = (HERE/'guest.sh').read_text()
        self.assertIn('Environment=REDIS_SOCKET=/run/redis/redis.sock', script)
        self.assertIn('Environment=REDIS_URI=unix:///run/redis/redis.sock', script)
        self.assertIn('Environment=REDIS_PASSWORD_FILE=/run/credentials/redis', script)
        self.assertNotIn('PublishPort=', script)
        self.assertIn('Environment=PUBSUB_RESOURCE_REDIS_URI=redis-proxy:6379', script)
        self.assertIn('Environment=PUBSUB_RESOURCE_REDIS_USERNAME=logma', script)
        self.assertIn('export PUBSUB_RESOURCE_REDIS_PASSWORD=', script)

    def test_live_configuration_restarts_only_logma(self):
        source = (HERE/'guest.sh').read_text()
        action = source.split('  configure-logma)',1)[1].split('  qualify)',1)[0]
        self.assertIn('write_units logma\n',action)
        self.assertIn('systemctl --user restart "$scope-logma.service"',action)
        self.assertNotIn('systemctl --user stop',action)
        self.assertIn('"$peers_before"',action)
        self.assertIn('resource-ready',action)

if __name__ == '__main__': unittest.main()
