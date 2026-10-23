# Agni local Fatline bootstrap

This is an **Agni-owned local development composition**. It does not modify
Agni's GCP/CoreOS placement paths or install host systemd units.

Run from the **Nix-Alpine container**, with Agni cloned into the mounted
workspace. The existing Nix-Alpine Makefile's clone target can be used to
clone `dash-xd/agni` into the mounted workspace; do not replace that Makefile.

```sh
cd /workspaces/agni/local/fatline
nix run .#bootstrap
nix run .#preflight
nix run .#build
nix run .#qualify
```

Or from the Nix-Alpine Makefile's host directory, if its run target maps
`FLAKE` into `/workspaces`:

```sh
make run FLAKE=agni/local/fatline TARGET='#bootstrap'
make run FLAKE=agni/local/fatline TARGET='#build'
make run FLAKE=agni/local/fatline TARGET='#qualify'
```

The local Makefile also supports `make bootstrap`, `make build`, and
`make qualify` from within the flake directory.

The initial bootstrap clones the selected Logma, Prajapati, and Smoke
branches into `.fatline-workspace/sources` and records exact commit SHAs
in `.fatline-workspace/refs.lock`. Subsequent commands require unchanged
checkouts at those SHAs. The mutable source tree is deliberately kept
outside the Nix store.

**Prerequisites:** Nix with flakes enabled, GitHub access to the three
repositories, and network access for the first Nix and Go dependency fetch.
The Nix-Alpine mount must be writable and persistent.

**Current test scope:** existing Prajapati authz tests, Logma graph model
tests, and Smoke compilation. This does **not** yet exercise a project-aware
Logma HTTP authorizer or prove Redis graph persistence. Those are the next
code changes; do not treat baseline success as security qualification.

The flake uses a Nixpkgs input and Go 1.26. Commit `flake.lock` after
generating it to freeze the Nixpkgs revision too.

## Versioning ownership

CalVer release naming, candidate/qualified tag semantics and qualification identity for artifacts built by Nix-Alpine belong to [Nix-Alpine's VERSIONING_IDIOMS.md](https://github.com/dash-xd/nix-alpine/blob/codex/make-bash-local-orchestration/VERSIONING_IDIOMS.md). Agni only declares Fatline component references and runtime topology. The currently configured CalVer references are reserved, not qualified or published; deployment requires externally authorized exact image-ID verification.

## Redis image ownership and service qualification

Agni no longer builds a Redis OCI image. The Redis image is built, imported,
and qualified by Nix-Alpine's `release/components/redis` flake and release
ledger. `composition.nix` accepts only a versioned
`localhost/nix-alpine/redis:qualified-YYYY.MM.DD[.MICRO]` reference for
Redis. The reserved `composition-config.nix` references are deliberately
not deployment-ready.

The host-only `scripts/qualify-redis-service.sh` inspects an independently
deployed Smoke-managed qualification unit. It refuses the production Fatline
unit, records the observed Podman image ID and Agni Quadlet/configuration
hashes, and **always fails** until socket ACL, lifecycle and restart recovery
are implemented. Do not substitute this identity probe for service
qualification or start a parallel ad-hoc Redis test container.
