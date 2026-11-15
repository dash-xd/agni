# Agni infrastructure composition

Agni owns infrastructure topology, VM construction, runtime service composition,
and application-specific qualification. Generic Nix/store/provider/SSH operations
belong in nix.xd; compiled GHXD, Go tool composition and reusable test primitives
belong in Smoke; Probot Runtime owns worker execution semantics.

The current architecture contract is
[local/fatline/qualification/architecture-v20261115.md](local/fatline/qualification/architecture-v20261115.md).
Coding agents should also read [AGENTS.md](AGENTS.md).

From the repository checkout:

```sh
make -C local/fatline qualification-check
make -C local/fatline architecture-qualify NIX_XD_DIR="$HOME/workspace/nix.xd20261115" SMOKE_CHECKOUT=smoke20261115
make -C local/fatline qualification QUALIFICATION=factory-live NIX_XD_DIR="$HOME/workspace/nix.xd20261115" PROVIDER=podman MACHINE=coreos-arm64 DEPLOYMENT=vm1
```

The architecture admission check is static and reports the existing Smoke
GHXD host adapter as **migration pending**. The Fatline factory-live gate
is an isolated runtime test, not permission to activate production services.
Do not conflate either with full native GHXD, process-restart, or systemd
lifecycle qualification.

For the optional Nix-Alpine-only GHXD candidate, first provision and qualify
`nix.xd/examples/ghxd-native-grants.json` during disposable owner bootstrap.
Then select `QUALIFICATION=source-sync-native` with
`GHXD_NATIVE_GRANTS_ACK=TRUST-NIX-ALPINE-OWNER`. This broadens the trusted
owner's access to the GHXD secret volume; keep the old GHXD host dispatcher
until the live source-sync and credential tests pass.
