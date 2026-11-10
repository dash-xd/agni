import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name('recovery.sh')
PROBE = '/nix/store/' + 'a'*32 + '-probe/bin/fatline-services-probe'


class BootstrapTransaction(unittest.TestCase):
    def exercise(self, fail=False):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            commands = home / 'bin'; commands.mkdir()
            for name, source in {
                'id':'echo 1001',
                'findmnt':'case "$*" in *FSTYPE*) echo 9p;; *) echo ro,trans=virtio;; esac',
                'podman':'if [ "${FAIL_BOOTSTRAP:-0}" = 1 ]; then exit 1; fi; echo FATLINE_FUNCTIONS_BOOTSTRAP=passed',
            }.items():
                path = commands / name
                path.write_text('#!/bin/sh\n' + source + '\n'); path.chmod(0o700)
            base = home / '.local/state/nix-xd/fatline/test'
            apps = base / 'services'; apps.mkdir(parents=True)
            (apps / 'bootstrap-template.acl').write_text('user default off\nuser bootstrap on #hash +ping\nuser logma on #other +ping\n')
            env = dict(os.environ, HOME=str(home), PATH=str(commands)+':'+os.environ['PATH'], INVOCATION_ID='one')
            def run(action, check=True):
                return subprocess.run(['bash', str(SCRIPT), action, 'test', PROBE], env=env, check=check, capture_output=True, text=True)
            run('service-prepare')
            runtime = base / 'credentials/runtime'
            self.assertIn('user bootstrap on', (runtime / 'users.acl').read_text())
            if fail: env['FAIL_BOOTSTRAP'] = '1'
            result = run('service-bootstrap', check=False)
            self.assertEqual(result.returncode != 0, fail)
            self.assertIn('user bootstrap reset off', (runtime / 'users.acl').read_text())
            self.assertIn('user logma on', (runtime / 'users.acl').read_text())
            self.assertEqual((runtime / 'users.acl').stat().st_mode & 0o777, 0o600)
            self.assertEqual((runtime / 'ready').exists(), not fail)
            self.assertIn('user bootstrap on', (apps / 'bootstrap-template.acl').read_text())
            if not fail:
                self.assertEqual((runtime / 'ready').read_text().strip(), 'one')
                run('service-stop')
                self.assertFalse((runtime / 'ready').exists())
                run('service-prepare')
                self.assertIn('user bootstrap on', (runtime / 'users.acl').read_text())

    def test_live_graph_rejects_missing_restart_relationship(self):
        with tempfile.TemporaryDirectory() as directory:
            commands = Path(directory)
            for name, source in {
                'id':'echo 1001',
                'findmnt':'case "$*" in *FSTYPE*) echo 9p;; *) echo ro;; esac',
                'systemctl': '''case "$*" in
*LoadState*) echo loaded;;
*ExecStartPre*) echo "service-prepare test $PROBE";;
*ExecStartPost*) echo "service-bootstrap test $PROBE";;
*ExecStopPost*) echo "service-stop test $PROBE";;
*PartOf*) [ "${MISSING_EDGE:-0}" = 1 ] || echo test-redis.service;;
*) echo 'test-redis.service test-nginx.service';;
esac''',
            }.items():
                path = commands / name
                path.write_text('#!/bin/sh\n' + source + '\n'); path.chmod(0o700)
            env = dict(os.environ, HOME=directory, PATH=directory+':'+os.environ['PATH'], PROBE=PROBE)
            command = ['bash', str(SCRIPT), 'graph-check', 'test', PROBE]
            self.assertEqual(subprocess.run(command, env=env, capture_output=True).returncode, 0)
            env['MISSING_EDGE'] = '1'
            self.assertNotEqual(subprocess.run(command, env=env, capture_output=True).returncode, 0)

    def test_success_revokes_runtime_and_file(self): self.exercise()
    def test_failed_bootstrap_revokes_file_and_never_marks_ready(self): self.exercise(fail=True)


if __name__ == '__main__': unittest.main()
