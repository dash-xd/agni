"""Agni-owned startup operations, executed by its flake inside Nix-Alpine."""
import argparse
import json
import os
from pathlib import Path
import platform
import sys

from nix_alpine_runtime import run, scoped_lock, write_json
from render import render

HERE=Path(__file__).resolve().parent


def main():
    parser=argparse.ArgumentParser()
    sub=parser.add_subparsers(dest='action',required=True)
    sub.add_parser('check')
    rendering=sub.add_parser('render')
    rendering.add_argument('--spec',required=True,type=Path)
    rendering.add_argument('--output',required=True,type=Path)
    args=parser.parse_args()
    if platform.system()!='Linux' or os.geteuid()==0:
        raise ValueError('Run the Agni flake through the unprivileged Nix-Alpine executor')
    if args.action=='check':
        for name in ('test_render.py','test_bootstrap.py'):
            run([sys.executable,str(HERE/name)],os.environ,timeout=60)
        print('AGNI_STARTUP_CHECK=passed executor=linux',flush=True)
    else:
        spec=json.loads(args.spec.read_text())
        output=args.output.resolve();output.parent.mkdir(parents=True,exist_ok=True)
        with scoped_lock(output.parent/(output.name+'.lock')):
            render(spec,output)
            write_json(output/'render-result.json',{'result':'passed','scope':spec['scope'],'operation':'render','applied':False})
        print('AGNI_STARTUP_RENDER=passed applied=false',flush=True)


if __name__=='__main__':
    try:main()
    except (ValueError,OSError) as error:print('Agni startup error: '+str(error),file=sys.stderr);sys.exit(1)
