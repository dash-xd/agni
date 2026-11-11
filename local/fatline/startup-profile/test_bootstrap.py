"""Exercise the bootstrap hook's success and failure cleanup with a fake engine."""
from pathlib import Path
import os
import subprocess
import tempfile
import unittest

HERE=Path(__file__).resolve().parent


class BootstrapCleanup(unittest.TestCase):
    def run_hook(self, failure):
        with tempfile.TemporaryDirectory() as directory:
            home=Path(directory);tools=home/'bin';tools.mkdir()
            for name,body in {
                'id':'echo 1001',
                'findmnt':'if [ "$3" = FSTYPE ]; then echo 9p; else echo ro; fi',
                'podman':'exit "${PROBE_EXIT:-0}"',
            }.items():
                path=tools/name;path.write_text('#!/bin/sh\n'+body+'\n');path.chmod(0o755)
            base=home/'.local/state/nix-xd/fatline/fixture';apps=base/'services';apps.mkdir(parents=True)
            (apps/'bootstrap-template.acl').write_text('user bootstrap on >fixture-password +@all\nuser default off\n')
            env=dict(os.environ,HOME=str(home),PATH=str(tools)+':'+os.environ['PATH'],INVOCATION_ID='fixture-invocation',PROBE_EXIT=str(failure))
            args=['bash',str(HERE/'bootstrap.sh')]
            probe='/nix/store/'+'a'*32+'-probe/bin/fatline-services-probe'
            subprocess.run(args+['prepare','fixture',probe],env=env,check=True)
            result=subprocess.run(args+['start','fixture',probe],env=env,capture_output=True,text=True)
            self.assertEqual(result.returncode,failure,result.stderr)
            runtime=base/'credentials/runtime'
            self.assertIn('user bootstrap reset off',(runtime/'users.acl').read_text())
            self.assertEqual((runtime/'users.acl').stat().st_mode & 0o777,0o600)
            self.assertEqual((runtime/'ready').exists(),not failure)
            if not failure:self.assertEqual((runtime/'ready').read_text().strip(),'fixture-invocation')

    def test_failed_probe_revokes_file_without_readiness(self):self.run_hook(17)
    def test_success_records_invocation_after_revocation(self):self.run_hook(0)


if __name__=='__main__':unittest.main()
