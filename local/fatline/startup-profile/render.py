#!/usr/bin/env python3
"""Render the complete rootless startup graph from one resolved profile."""
import json
from pathlib import Path
import re
import sys


def render(spec, output):
    if spec.get('schema')!=1 or not re.fullmatch(r'[a-z][a-z0-9-]{0,31}',spec['scope']):raise ValueError('Invalid profile scope')
    for key in ('home','bundle'):
        if not re.fullmatch(r'/[A-Za-z0-9/_.+-]+',spec[key]):raise ValueError('Invalid profile path')
    for key in ('archive','redis','nginx','logma','skymill','probe'):
        if not re.fullmatch(r'/nix/store/[a-z0-9]{32}-[A-Za-z0-9._+-]+(?:/[A-Za-z0-9/_.+-]+)?',spec[key]):raise ValueError('Invalid immutable executable/archive path')
    if type(spec['port']) is not int or not 1024<=spec['port']<=65535:raise ValueError('Invalid proxy port')
    if not re.fullmatch(r'[a-f0-9]{64}',spec['aclDigest']):raise ValueError('Invalid ACL digest')
    scope=spec['scope'];base=spec['home']+'/.local/state/nix-xd/fatline/'+scope;apps=base+'/services'
    shared='/var/mnt/nixstore/'+spec['bundle'].removeprefix('/nix/store/')
    output.mkdir(mode=0o700,parents=True,exist_ok=True)
    (output/'manifest.json').write_text(json.dumps(spec,sort_keys=True,indent=2)+'\n')
    import shlex
    (output/'profile.env').write_text('\n'.join(key+'='+shlex.quote(str(value)) for key,value in {
        'profile_scope':scope,'profile_archive':spec['archive'],'profile_probe':spec['probe'],
        'profile_acl_digest':spec['aclDigest'],'profile_bundle':shared}.items())+'\n')
    (output/(scope+'.network')).write_text('[Network]\nNetworkName=nix-xd-'+scope+'\nInternal=true\n')
    for role in ('redis','nginx','logma','skymill'):
        lines=['[Unit]','Description=Fatline '+scope+' '+role,'StartLimitIntervalSec=120','StartLimitBurst=3']
        if role=='redis':lines+=['Upholds='+' '.join(scope+'-'+child+'.service' for child in ('nginx','logma','skymill'))]
        if role!='redis':lines+=['Requires='+scope+'-redis.service','After='+scope+'-redis.service','BindsTo='+scope+'-redis.service','PartOf='+scope+'-redis.service']
        if role=='logma':lines+=['Requires='+scope+'-nginx.service','After='+scope+'-nginx.service','BindsTo='+scope+'-nginx.service']
        lines+=['[Container]','ContainerName='+scope+'-'+role,'Rootfs='+ (base if role in ('redis','nginx') else apps)+'/rootfs',
            'User=1000:1000','UserNS=keep-id:uid=1000,gid=1000','ReadOnly=true','NoNewPrivileges=true','DropCapability=all',
            'PodmanArgs=--read-only-tmpfs=false --security-opt label=disable','Volume=/var/mnt/nixstore:/nix/store:ro',
            'Tmpfs=/tmp:rw,nosuid,nodev,mode=1777,size=4m']
        if role=='redis':lines+=['Network=none','Volume='+base+'/socket:/run/redis:rw',
            'Volume='+base+'/credentials/runtime:/run/bootstrap-acl:ro','Volume='+base+'/config/redis.conf:/etc/redis.conf:ro',
            'Exec='+spec['redis']+' /etc/redis.conf']
        else:lines+=['Network='+scope+'.network','NetworkAlias='+('redis-proxy' if role=='nginx' else role),'Volume='+base+'/socket:/run/redis:ro']
        if role=='nginx':lines+=['PublishPort=127.0.0.1:'+str(spec['port'])+':6379','Volume='+base+'/config/nginx.conf:/etc/nginx.conf:ro',
            'Exec='+spec['nginx']+' -e /dev/stderr -g "daemon off;" -c /etc/nginx.conf']
        if role in ('logma','skymill'):lines+=['Volume='+apps+'/credentials/'+role+':/run/credentials:ro','Environment=FATLINE_SCOPE='+scope]
        if role=='logma':lines+=['Volume='+apps+'/state/logma:/var/lib/logma/lifecycle:rw',
            'Environment=REDIS_NETWORK=unix','Environment=REDIS_SOCKET=/run/redis/redis.sock','Environment=REDIS_URI=unix:///run/redis/redis.sock',
            'Environment=REDIS_USERNAME=logma','Environment=PUBSUB_RESOURCE_REDIS_URI=redis-proxy:6379','Environment=PUBSUB_RESOURCE_REDIS_USERNAME=logma',
            'Environment=LOGMA_RATELIMITER_BOOTSTRAP=external','Environment=LOGMA_LIFECYCLE_STATE_DIR=/var/lib/logma/lifecycle','Environment=LOGMA_BIND_ADDR=0.0.0.0',
            'Exec=/bin/sh -ec \'export REDISCLI_AUTH="$(/bin/busybox cat /run/credentials/redis)"; export PUBSUB_RESOURCE_REDIS_PASSWORD="$(/bin/busybox cat /run/credentials/redis)"; export API_KEY="$(/bin/busybox cat /run/credentials/api-key)"; exec "'+spec['logma']+'"\'']
        if role=='skymill':lines+=['Environment=REDIS_URL=unix:///run/redis/redis.sock','Environment=REDIS_USERNAME=skymill',
            'Environment=REDIS_PASSWORD_FILE=/run/credentials/redis','Environment=SKYMILL_LISTEN_ADDR=0.0.0.0:8081',
            'Environment=SKYMILL_SCOPED_PROVIDER=true','Environment=SKYMILL_STREAM='+scope+':skymill:stream:github.webhooks','Exec='+spec['skymill']]
        lines+=['[Service]','ExecStartPre=/bin/bash '+apps+'/boot-wait.sh '+scope+' '+spec['probe'],'TimeoutStartSec=300',
            'Restart=on-failure','RestartSec=5']
        if role=='redis':lines+=['ExecStartPre=/bin/bash '+shared+'/bootstrap.sh prepare '+scope+' '+spec['probe'],
            'ExecStartPost=/bin/bash '+shared+'/bootstrap.sh start '+scope+' '+spec['probe'],
            'ExecStopPost=/bin/bash '+shared+'/bootstrap.sh stop '+scope+' '+spec['probe']]
        lines+=['[Install]','WantedBy=default.target']
        (output/(scope+'-'+role+'.container')).write_text('\n'.join(lines)+'\n')
    (output/'redis.conf').write_text('port 0\nprotected-mode yes\nunixsocket /run/redis/redis.sock\nunixsocketperm 600\nsave ""\nappendonly no\nmaxmemory 40mb\nmaxmemory-policy noeviction\ndatabases 1\naclfile /run/bootstrap-acl/users.acl\n')
    (output/'nginx.conf').write_text('worker_processes 1;\npid /tmp/nginx.pid;\nerror_log /dev/stderr warn;\nevents { worker_connections 128; }\nstream { server { listen 6379; proxy_connect_timeout 5s; proxy_timeout 1h; proxy_pass unix:/run/redis/redis.sock; } }\n')


if __name__=='__main__':render(json.loads(Path(sys.argv[1]).read_text()),Path(sys.argv[2]))
