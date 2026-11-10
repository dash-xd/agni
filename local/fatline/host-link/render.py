#!/usr/bin/env python3
"""Render private qualification credentials and scoped, non-secret service files."""
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import sys


def render(root, scope, port):
    if not re.fullmatch(r'[a-z][a-z0-9-]{0,31}', scope) or not 1024 <= port <= 65535:
        raise ValueError('invalid scope or port')
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(root, 0o700)
    passwords = {role: secrets.token_hex(32) for role in ('publisher', 'subscriber')}
    acl = ['user default off']
    for role, password in passwords.items():
        (root / role).write_text(password + '\n')
        os.chmod(root / role, 0o600)
        commands = '+ping +hello +client|setinfo '
        if role == 'publisher':
            commands += '+publish +get +set'
            keys = '~' + scope + ':qualification:*'
        else:
            commands += '+subscribe +unsubscribe'
            keys = ''
        acl.append('user ' + role + ' reset on #' + hashlib.sha256(password.encode()).hexdigest() +
                   ' -@all resetkeys resetchannels ' + keys + ' &' + scope + ':qualification ' + commands)
    (root / 'users.acl').write_text('\n'.join(acl) + '\n')
    os.chmod(root / 'users.acl', 0o600)
    (root / 'redis.conf').write_text('port 0\nprotected-mode yes\nunixsocket /run/redis/redis.sock\nunixsocketperm 600\n'
        'save ""\nappendonly no\nmaxmemory 40mb\nmaxmemory-policy noeviction\ndatabases 1\naclfile /run/credentials/users.acl\n')
    (root / 'nginx.conf').write_text('worker_processes 1;\npid /tmp/nginx.pid;\nerror_log /dev/stderr warn;\n'
        'events { worker_connections 128; }\nstream { server { listen 6379; proxy_connect_timeout 5s; '
        'proxy_timeout 1h; proxy_pass unix:/run/redis/redis.sock; } }\n')
    return passwords


if __name__ == '__main__':
    render(Path(sys.argv[1]), sys.argv[2], int(sys.argv[3]))
