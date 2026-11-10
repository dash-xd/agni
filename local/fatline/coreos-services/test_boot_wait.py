import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT=Path(__file__).with_name('boot-wait.sh')


class StoreBarrier(unittest.TestCase):
    def test_waits_for_read_only_9p_instead_of_accepting_another_mount(self):
        with tempfile.TemporaryDirectory() as directory:
            root=Path(directory)
            for name, body in {
                'findmnt': 'if [ ! -f "$HOME/ready" ]; then echo tmpfs; elif [ "$3" = FSTYPE ]; then echo 9p; else echo ro,nodev; fi',
                'sleep': 'touch "$HOME/ready"',
            }.items():
                path=root/name
                path.write_text('#!/bin/sh\n'+body+'\n');path.chmod(0o700)
            env=dict(os.environ,HOME=directory,PATH=directory+':'+os.environ['PATH'])
            result=subprocess.run(['bash',str(SCRIPT),'scope'],env=env,capture_output=True,text=True,timeout=5)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertTrue((root/'ready').exists())
            self.assertIn('FATLINE_BOOT_STORE_READY=passed',result.stdout)


if __name__=='__main__':unittest.main()
