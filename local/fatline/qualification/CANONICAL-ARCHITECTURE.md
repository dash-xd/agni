# Agni and Fatline canonical composition contract (2026-11-16)

Status: normative design and migration plan, **not a live-pass statement**. Read this together with `architecture-v20261115.md` and `architecture-sources.json`.

## Source of truth and separation

Agni owns VM identities and declared topology, provider selection for guests, CoreOS generation, systemd Quadlets, service ACLs, activation guards, placement bindings, guest-side invariants and application-specific gate acceptance. nix.xd is generic Nix-Alpine execution, store/grant, immutable source staging, SSH guest transport and logging; it must never embed Fatline/Shoal/Probot placement logic. Smoke owns composed Go operations, GHXD/device auth, secret refresh and source generations. Probot Runtime owns webhook delivery, subscription factory, fences, acknowledgments and externally visible idempotent effects.

Canonical path: **Mac bootstrap -> nix.xd Nix-Alpine runner -> pinned Agni flake -> Smoke executable or Agni-owned guest package -> generic nix.xd guest transport -> CoreOS systemd/Podman**. Make is a thin selector: `make -C local/fatline qualification QUALIFICATION=<gate>`. Do not implement a second host-side orchestrator inside Agni Make or Shell.

## Deny old idioms for ALL new work

- Do not add new `deployment-*` workflows or extend `operations/deployment-compat.mk`. Historical aliases are available for existing evidence only.
- Do not add Mac Podman commands, host `project-host-run`, host-action scripts or `PROVIDER=container` canonical paths. The old `operations/guest-migration.sh` GHXD caller is a documented exception awaiting retirement.
- Do not place application policy in nix.xd, duplicate Smoke GitHub credential operations, or treat a shell rewrite as migration.
- Do not use mutable branch tips as execution identity, switch implicitly to another dated workspace, store secrets in derivations, or use unscoped state under checkout-local `.state`.
- Do not infer VM identity from a port name or static placement alone: bind declared logical instance to observed boot ID / host-key fingerprint / backing resource and verify at runtime.
- Do not claim a gate passed from its scripted marker strings; do not let a static architecture check imply CoreOS activation.
- Do not add production rollback/failover/version-compatibility infrastructure to this destroyable Mac qualification unless scope is explicitly extended.

## Ordered gates

1. Source-lock verification for nix.xd, Smoke, Agni and Probot revisions. Full 40-hex SHA, clean/committed staged source and source-closure records. Lock changes require a new candidate and affected requalification.
2. Cross-repository architecture checks: Agni policy + nix.xd owner audit + Smoke check running in Nix-Alpine. Structural only; no fabricated live result.
3. Native GHXD grants, credential refresh, source sync, wrong-SHA refusal and one-writer tests on a disposable selected owner, without concurrent legacy sidecar.
4. Fatline `factory-live`: real Redis/Skymill/Probot execution, two subscription groups, recovery with one externally observable effect per group and unchanged original VM1 service invocation identifiers.
5. Separately supervised CoreOS systemd/Quadlet lifecycle: kill a processor, restart it under systemd, reclaim pending Redis Stream work without duplicate external effects, verify other worker uninterrupted, capture journal and cleanup.
6. Only after those observed passes: explicit Agni activation decision, with credentials/ACLs/ports/service identity validated. No automatic promotion.

Each gate requires exact SHA pins, explicit test environment, side-effect scope, negative tests, stable pass/fail marker, exit code, stdout+stderr, artifact paths and cleanup. An earlier pass does not automatically certify a changed contract.

## Native GHXD transition

`QUALIFICATION=source-sync-native` selects the candidate Smoke `#ghxd-native` via nix.xd's generic runner. The original selected Nix-Alpine owner must have been bootstrapped with `examples/ghxd-native-grants.json`; `grants-verify` must pass before auth or source actions. `GHXD_NATIVE_GRANTS_ACK=TRUST-NIX-ALPINE-OWNER` acknowledges the larger writable secret trust boundary. It does **not** grant access. The current host adapter remains until independent refresh and source-sync live evidence is observed, and the legacy and native controllers must never write simultaneously.

Do not extend `guest-migration.sh` to work around a missing grant. Fix provider/transport in nix.xd, GHXD workflow in Smoke or application acceptance in Agni as appropriate.

## Workspace and operational conventions

CalVer for branches, immutable SHA for execution. Log nix.xd actions under `~/.local/nix.xd/logs`, persistent host resources under `~/.local/state/nix-xd`; use named Podman volumes or 9P grants for VM and credential state. Retain rootless/SELinux isolation, single-writer Nix stores and readonly consumers. Mac sandbox can be reset rather than introducing failover and migration scaffolding.

## Operator path (candidate, not observed pass)

```sh
make -C local/fatline qualification-check
make -C local/fatline architecture-qualify NIX_XD_DIR=/absolute/path/to/nix.xd20261127 SMOKE_CHECKOUT=smoke20261127 PROVIDER=podman MACHINE=coreos-arm64
make -C local/fatline qualification QUALIFICATION=source-sync-native GHXD_NATIVE_GRANTS_ACK=TRUST-NIX-ALPINE-OWNER NIX_XD_DIR=/absolute/path/to/nix.xd20261127 SMOKE_CHECKOUT=smoke20261127 PROVIDER=podman MACHINE=coreos-arm64
make -C local/fatline qualification QUALIFICATION=factory-live DEPLOYMENT=vm1 NIX_XD_DIR=/absolute/path/to/nix.xd PROVIDER=podman MACHINE=coreos-arm64
```

These commands are **not** permission to run source sync before native grants are verified or to claim supervised lifecycle qualification from factory-live. Recheck the source lock before any live run.
