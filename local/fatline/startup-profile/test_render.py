import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

HERE=Path(__file__).resolve().parent
module=importlib.util.spec_from_file_location('startup_render',HERE/'render.py')
renderer=importlib.util.module_from_spec(module);module.loader.exec_module(renderer)


class ProfileContract(unittest.TestCase):
    def spec(self):
        prefix='/nix/store/'+'a'*32+'-fixture'
        return dict(schema=1,scope='fatline-arm-vm1',home='/home/wisp',bundle=prefix,port=16379,archive=prefix,
            redis=prefix+'/bin/redis-server',nginx=prefix+'/bin/nginx',logma=prefix+'/bin/api',skymill=prefix+'/bin/skymill-http',
            probe=prefix+'/bin/fatline-services-probe',aclDigest='b'*64)

    def test_complete_graph_has_ordering_private_mounts_and_no_password_values(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory);renderer.render(self.spec(),root)
            self.assertEqual(len(list(root.glob('*.container'))),4)
            redis=(root/'fatline-arm-vm1-redis.container').read_text()
            self.assertIn('ExecStartPost=/bin/bash ',redis)
            self.assertIn('/bootstrap.sh start ',redis)
            self.assertIn('Restart=on-failure',redis)
            self.assertIn('RestartSec=5',redis)
            self.assertIn('StartLimitBurst=3',redis)
            self.assertIn('Upholds=fatline-arm-vm1-nginx.service fatline-arm-vm1-logma.service fatline-arm-vm1-skymill.service',redis)
            self.assertLess(redis.index('/boot-wait.sh'),redis.index('/bootstrap.sh prepare'))
            for role in ('nginx','logma','skymill'):
                unit=(root/('fatline-arm-vm1-'+role+'.container')).read_text()
                self.assertIn('Requires=fatline-arm-vm1-redis.service',unit)
                self.assertIn('After=fatline-arm-vm1-redis.service',unit)
                self.assertIn('BindsTo=fatline-arm-vm1-redis.service',unit)
                self.assertIn('Volume=/var/mnt/nixstore:/nix/store:ro',unit)
                if role!='nginx':self.assertNotIn('PublishPort=',unit)
            logma=(root/'fatline-arm-vm1-logma.container').read_text()
            self.assertIn('After=fatline-arm-vm1-nginx.service',logma)
            self.assertIn('PUBSUB_RESOURCE_REDIS_URI=redis-proxy:6379',logma)
            self.assertIn('/run/credentials/api-key',logma)
            self.assertNotIn('Environment=API_KEY=',logma)
            self.assertIn('aclfile /run/bootstrap-acl/users.acl',(root/'redis.conf').read_text())

    def test_untrusted_shell_fragments_are_rejected_before_rendering(self):
        with tempfile.TemporaryDirectory() as directory:
            spec=self.spec();spec['home']='/home/wisp; bad-command'
            with self.assertRaisesRegex(ValueError,'Invalid profile path'):renderer.render(spec,Path(directory))


if __name__=='__main__':unittest.main()
