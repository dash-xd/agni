# Agni — contributor/agent contract

Read [local/fatline/qualification/architecture-v20261115.md](local/fatline/qualification/architecture-v20261115.md) before changing VM/Quadlet/topology or Fatline tests.

- Agni owns topology, systemd Quadlets, service ACLs, guest admission and acceptance; it consumes generic nix.xd transport and Smoke composed executables.
- Use exact SHA locks and CalVer zero-version branches. Keep a stable test marker and meaningful negative tests. Store secrets in volume mounts, never the Nix store.
- Canonical Fatline operator entry: `make -C local/fatline qualification QUALIFICATION=...`; `deployment-*` targets are preserved in `operations/deployment-compat.mk` only for old callers and evidence.
- Do **not** introduce new app-specific nix.xd Make targets or Mac Podman orchestration in Agni.
- The macOS/CoreOS sandbox is disposable; do not add production rollback/failover/migration logic as a precondition for new tests.
- Passed CoreOS generator and Node factory gates are historical evidence. The `factory-live` CoreOS gate still requires an observed pass; systemd process SIGKILL/restart is a distinct gate.
- Run `make -C local/fatline qualification-check`, then only the new requested live gate. Preserve the five existing VM1 services' `InvocationID`s.

## Exact architecture source lock

The cross-repository architecture test is pinned by
`local/fatline/qualification/architecture-sources.json`. Do not substitute
the latest moving branch head after a qualification. Update the lock in a
new CalVer candidate, then rerun `architecture-verify-sources`,
`architecture-qualify` and the affected live gate. This guards against
silent interface drift when entering a new chat session or workspace.
