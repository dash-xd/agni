#!/usr/bin/env python3
"""Extend an existing qualification scope with separately mounted application identities."""
import hashlib
import json
import os
from pathlib import Path
import secrets
import subprocess
import sys


def render(bundle, original, out, scope):
    if out.exists():
        raise ValueError('Application credentials already exist; reuse the prepared generation')
    out.mkdir(mode=0o700, parents=True)
    policy = json.loads((bundle / 'acl-policy.json').read_text())
    policy.update(scope=scope, skymillStream=scope + ':skymill:stream:github.webhooks')
    policy_path = out / 'policy.json'
    policy_path.write_text(json.dumps(policy, sort_keys=True) + '\n')
    for role in ('logma', 'skymill', 'bootstrap'):
        role_dir = out / role
        role_dir.mkdir(mode=0o700)
        secret = secrets.token_hex(32)
        (out / role / 'redis').write_text(secret + '\n')
        os.chmod(out / role / 'redis', 0o600)
        # Reuse Agni's tracked production renderer without changing its policy.
        (out / (role + '.secret')).write_text(secret + '\n')
        os.chmod(out / (role + '.secret'), 0o600)
    temporary = out / 'render-input'
    temporary.mkdir(mode=0o700)
    for role in ('logma','skymill','bootstrap'):
        (temporary / role).write_text((out / (role + '.secret')).read_text())
        os.chmod(temporary / role, 0o600)
        (out / (role + '.secret')).unlink()
    subprocess.run([sys.executable, str(bundle / 'render-users-acl.py'), str(policy_path), str(temporary), str(out / 'users.acl')], check=True, stdout=subprocess.DEVNULL)
    for path in temporary.iterdir(): path.unlink()
    temporary.rmdir()
    existing = (original / 'users.acl').read_text().splitlines()
    if {line.split()[1] for line in existing} != {'default','publisher','subscriber'}:
        raise ValueError('Unexpected original qualification ACL identities')
    with (out / 'users.acl').open('a') as acl:
        acl.write('\n'.join(line for line in existing if not line.startswith('user default ')) + '\n')
    os.chmod(out / 'users.acl', 0o600)
    (out / 'logma/api-key').write_text(secrets.token_hex(32) + '\n')
    os.chmod(out / 'logma/api-key', 0o600)
    (out / 'digest').write_text(hashlib.sha256((out / 'users.acl').read_bytes()).hexdigest() + '\n')


if __name__ == '__main__':
    render(Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3]), sys.argv[4])
