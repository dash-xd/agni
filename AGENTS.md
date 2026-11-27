# Agni — binding contributor and agent policy

**MANDATORY before editing topology, guests, Make or Fatline tests:** Read [local/fatline/qualification/CANONICAL-ARCHITECTURE.md](local/fatline/qualification/CANONICAL-ARCHITECTURE.md), then [local/fatline/qualification/architecture-v20261115.md](local/fatline/qualification/architecture-v20261115.md) and the [source lock](local/fatline/qualification/architecture-sources.json). The canonical document governs **new changes**; old examples and compatibility code are noncanonical.

**MANDATORY before qualification, merge or cleanup:** Read [POST-QUALIFICATION-CLEANUP.md](local/fatline/qualification/POST-QUALIFICATION-CLEANUP.md). Never clean a resource or branch without identifying its owner and confirming it is unreferenced. Architecture guards must allow legacy inventory to shrink, never expand.

- **Agni owns** CoreOS VM identity and topology, Quadlets, service ACLs, declarative guest plans, activation and application acceptance gates. **nix.xd owns only** generic bootstrap/provider, immutable source import, store/mount/grant operations, Nix-Alpine runner, SSH guest transport and evidence. **Smoke owns** Go GHXD device authentication, SOPS+age source generation and generic qualifier mechanism; Probot Runtime owns webhook/subscription behavior.
- The canonical operator interface is `make -C local/fatline qualification QUALIFICATION=...`. Make selects pinned Nix apps; it does not become a second orchestration engine. Do not add new `deployment-*` compatibility workflows, application-specific nix.xd Make targets, macOS Podman application setup, `project-host-run`, `host-actions`, or `PROVIDER=container` runtime paths.
- `operations/guest-migration.sh` GHXD and `operations/deployment-compat.mk` are **quarantined exceptions**. Inventory and migrate callers before removing; do not copy, extend or cite them as architectural precedent.
- Use zero-version CalVer development branches and *exact 40-hex SHAs* for execution. Never select moving branch heads or a dated checkout by implicit default. Any source-lock change requires a new candidate and affected qualification.
- Rootless mounts, one-writer Nix store and readonly readers; secrets only in runtime SOPS+age volumes, never `/nix/store` or code. Persistent state under `~/.local/state/nix-xd`, logs under `~/.local/nix.xd/logs`.
- A declared Shoal/Farcaster binding must identify the observed VM instance/boot and host key; do not confuse static plans with the running machine.
- **Do not mark PASS** from presence of expected strings, static checks or previous unrelated gates. The GHXD-native candidate, live factory, and supervised SIGKILL/systemd lifecycle are **distinct, currently unqualified gates**. Original VM1 service InvocationIDs must stay unchanged during candidate tests.
- The macOS/CoreOS qualification sandbox is destroyable. Do not build production failover, rollback, compatibility or migration machinery for this test environment.

Required gates: `make -C local/fatline qualification-check`, cross-repo `architecture-qualify` with exact source-lock checks, then the selected live gate on the actual CoreOS VM. GHXD-native secret grants require separate explicit trust acknowledgment, mount verification and independent credential-refresh validation. Never claim completion before observed evidence.

For a design conflict, follow the canonical contract rather than copying legacy code; change the policy and executable guard in the same reviewed commit if intentionally changing architecture.
