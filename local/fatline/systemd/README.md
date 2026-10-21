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

## Source reconciliation (2026-10-21)

- `xd-dash/logma` branch `codex/group-strength-resources` exposes `packages.x86_64-linux.image`, but it is a **monolithic** s6-overlay cell running its own Redis and Nginx. It cannot be used as the provider-only image in this composition. Reuse its `packages.x86_64-linux.logma` Go binary derivation in a new provider-only image built in the owning Logma repository, preserving Logma's existing `REDIS_NETWORK=unix` / `REDIS_SOCKET` contract.
- `xd-dash/skymill` branch `codex/httpapi-durable-delivery` has no `flake.nix` in the inspected tree. Define and qualify its provider-only OCI image in Skymill before pinning a digest.
- `xd-dash/smoke` branch `integration/smoke-reconcile-20261016` does not expose a confirmed Fatline Quadlet deployment API in the inspected tree. Do not claim Smoke installation or activation exists.
- Redis image and the two provider images remain unset in `composition-config.nix`; deployment is intentionally blocked.
- The generated Quadlets still need confirmed shared Unix-socket ownership/permissions and Redis ACL policy. No fabricated ACL principals or passwords are included.

Next implementation should be **in the owning repositories**: provider-only Logma and Skymill Nix image outputs, a qualified Redis image digest, a Smoke consumer for Agni's immutable output, and integration evidence. Do not introduce a second runtime orchestrator or launch Redis from test scripts.
