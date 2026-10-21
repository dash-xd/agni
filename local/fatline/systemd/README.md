# Fatline declarative deployment

Canonical source: `../composition-config.nix` and `../composition.nix`. The flake package `fatline` generates `quadlets/*.container` and `config/redis.conf` in one immutable Nix store output.

The files in this directory are **legacy candidates**, not the authoritative deployment input. Do not install them or use their unqualified image tags.

Run from the existing Nix-Alpine workspace:

```sh
make run FLAKE=agni/local/fatline TARGET='#preflight'
# Once image digests are qualified and recorded in composition-config.nix:
# nix build /workspaces/agni/local/fatline#fatline
```

The package intentionally cannot build until Redis, Logma and Skymill OCI image references are supplied as sha256 digest-pinned references. Nix-Alpine builds artifacts; it does not supervise Fatline services.

Deployment remains unimplemented: Smoke must consume the resulting store artifact, install the Quadlets under the appropriate host systemd manager, provision an independently qualified ACL file and credentials, and validate the runtime. Neither an ACL policy nor runtime readiness is implied by generating units.

Outstanding gates: verified provider image builds and digest pins, Redis ACL authority reconciliation, socket UID/GID and SELinux access, Podman generator compatibility in the target host, provider config schema, systemd activation and restart recovery, non-destructive Logma/Skymill integration tests. Never run destructive Redis tests against the shared service.
