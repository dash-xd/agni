#!/usr/bin/env python3
"""Render a minimal Butane composition with an administrative core account."""
import argparse
import pathlib
import re

USER = re.compile(r"[a-z_][a-z0-9_-]{0,31}\Z")


def key_from_file(path: str) -> str:
    parts = pathlib.Path(path).read_text().strip().split()
    if len(parts) < 2 or parts[0] not in {"ssh-ed25519", "ssh-rsa", "ecdsa-sha2-nistp256"}:
        raise SystemExit("Expected an SSH public key file")
    return " ".join(parts[:2])


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--core-key", required=True)
    parser.add_argument("--login-user", default="")
    parser.add_argument("--login-key")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    if args.login_user and (not USER.fullmatch(args.login_user) or args.login_user in {"core", "root"}):
        parser.error("login-user must be a distinct valid Linux username")
    if bool(args.login_user) != bool(args.login_key):
        parser.error("--login-user and --login-key must be provided together")

    core_key = key_from_file(args.core_key)
    document = f"""variant: fcos
version: 1.6.0
passwd:
  users:
    - name: core
      groups:
        - wheel
      ssh_authorized_keys:
        - {core_key}
"""
    if args.login_user:
        login_key = key_from_file(args.login_key)
        document += f"""    - name: {args.login_user}
      shell: /bin/bash
      ssh_authorized_keys:
        - {login_key}
"""
    document += """storage:
  files:
    - path: /etc/sudoers.d/90-starseed-core
      mode: 0440
      contents:
        inline: |
          core ALL=(ALL) NOPASSWD:ALL
    - path: /etc/zincati/config.d/90-starseed-qualification.toml
      mode: 0644
      contents:
        inline: |
          [updates]
          enabled = false
"""
    target = pathlib.Path(args.output)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(document)


if __name__ == "__main__":
    main()
