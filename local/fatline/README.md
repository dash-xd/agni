# Fatline qualification

Agni owns Fatline's composition, source pins, ACL policy, runtime assertions, and qualification plan. The plan is exposed as the `qualify-plan` flake app. Nix-Alpine owns the generic Make dispatcher and runtime adapter; this directory intentionally has no application Makefile.

From the Nix-Alpine checkout, invoke the plan through its generic Make interface:

```sh
make qualify-plan \
  PLAN_REPO=dash-xd/agni \
  PLAN_BRANCH=codex/coreos-fatline-qemu \
  PLAN_REV=<full-agni-commit-sha> \
  PLAN_CHECKOUT=compositions/agni \
  PLAN_FILE=local/fatline/qualification/plan.json \
  PLAN_FLAKE=local/fatline \
  PLAN_TARGET=qualify-plan \
  PLAN_SOURCES=local/fatline/qualification/sources.tsv \
  PLAN_GATE=all
```

The exact source revision is part of the qualification input. The source manifest resolves component checkouts at their recorded commit IDs. Artifact identity manifests may be passed through Nix-Alpine's generic artifact option.

The plan uses the `nix.xd qualification-plan/v1` module protocol. Each module declares a kind, phases, inputs, outputs, dependencies, and cleanup policy. Gates select module entry points; Agni resolves their dependency graph and runs shared prerequisites once. The module executor currently maps artifact builds, provider builds, ACL policy checks, and Podman/systemd composition gates to Agni-owned handlers. Runtime modules clean up by default; `RETAIN=1` preserves only the final selected runtime for inspection.

The Podman/systemd gates exercise the host topology through Nix-Alpine's rootless Podman socket and user systemd bus. This does not qualify CoreOS/QEMU or GCP. Those are separate runtime adapters and must report only the capabilities they actually provide.

Keep credential material outside the checkout. The tracked ACL policy contains no plaintext credentials; render deployment ACL files from protected credential inputs and qualify the generated policy on the selected runtime topology.

## Probot webhook integration: native ARM64 artifact gate

The `#qualify-integration` app accepts `--scenario probot-webhook --phase preflight|artifacts|live`.
The previously qualified `preflight` checks exact source markers and runs the Probot
Skymill/Logma Node client contract tests.

`--phase artifacts` reuses the same pinned source manifest and produces
`skymill-http` (`cmd/skymill-http`) and `logma-lifecycle`
(`cmd/api-lifecycle`) with Go 1.26, `CGO_ENABLED=0`, and the Linux ARM64
target. It checks build metadata and registers each result as a Nix GC root
under the Nix-Alpine writer's state directory. Probot's staged manifest and lockfile are checked, locked production npm
dependencies are installed without lifecycle scripts, and the resulting
Node runtime directory is stored and GC-rooted. **Immutable OCI packaging,
CoreOS deployment, and GitHub webhook delivery are not included in this phase**. These are
explicit follow-on gates rather than implicit success claims.

The older `coreos-services-vm1` package already orchestrates Logma and
Skymill guest-side user-systemd services with isolated Redis credentials.
It references older pinned upstream source revisions and must not be
silently promoted as proof that the new Probot source manifest is running.
A subsequent live composition must bind the new native artifacts to
that existing Agni guest contract and add the Probot service, then verify
GitHub App installation credentials independently of GHXD user OAuth.

`--phase live` deliberately runs source checks and the artifact gate
but fails closed with
`AGNI_PROBOT_WEBHOOK_INTEGRATION=blocked` until guest service and
GitHub authority wiring are qualified. A successful build is not a
webhook-settlement or Logmash/SSE observation qualification.


## CoreOS VM1 Probot guest-plan qualification

The next additive gate is
`#qualify-integration --scenario probot-webhook --phase guest-plan`.
It reuses the exact SHA source selection, the already-qualified Node/Go
application artifacts and the existing `coreos-services-vm1` rootless
user-Quadlet conventions. The writer produces a non-secret
`~/.local/state/agni/probot-webhook/artifacts.json`, then Agni's
`coreos-services/probot-plan.py` validates and emits
`~/.local/state/agni/probot-webhook/guest-plan-vm1.json`.

The plan is **not** transferred to CoreOS or installed. It contains
three candidate private-service Quadlets, exact source and Nix-store
identities, rootless/read-only mount conventions, role-specific expected
credential filenames and an explicit activation blocker. The gate runs
the unit and credential contract tests before emitting the candidate.
No GHXD OAuth token is used for a GitHub App installation.

The current CoreOS service package and its Redis ACL profile still
target older Logma/Skymill sources. The new Skymill's SHA-based Redis
binding keyspace is incompatible with those old ACL patterns. A future
`--phase live` must first bind the application roles and their own
scoped ACLs, then provision the App authority and verify a real webhook
through Skymill durable settlement and both Logma observers. It remains
fail-closed until those changes are complete.

## Deployment operations (first-class Agni interface)

From the Agni checkout, choose the deployment and intended lifecycle operation.
The `local/fatline/Makefile` intentionally exposes **no** JSON array, Nix
store path, source hash or assessment digest to the operator:

```sh
make -C local/fatline deployment-verify DEPLOYMENT=vm1
make -C local/fatline deployment-assess DEPLOYMENT=vm1
make -C local/fatline deployment-review DEPLOYMENT=vm1
make -C local/fatline deployment-migrate-stage DEPLOYMENT=vm1
```

The checked-in `vm1` deployment selects the
`fatline-arm-vm1` application scope and `starwisp` guest adapter.
The host-side workflow invokes generic nix.xd `stage`, qualifies the exact
immutable application bundle, captures its store identity, qualifies and
captures current guest adoption evidence, checks migration compatibility
and finally stages a private five-role candidate. All values are pinned
**per invocation**, not inferred from an unspecified `latest` file.
The SSH adapter still accepts `ARGS_JSON` internally; only Agni constructs
it. nix.xd remains independent of deployment names and application phases.

For the sibling workspace layout the Makefile defaults to
`../../../nix.xd20261112`; override `NIX_XD_DIR` for other checkouts.
Host-specific SSH identity, port, VM and state root can be configured via
`GUEST_SSH_KEY`, `GUEST_SSH_PORT`, `GUEST_VM_INSTANCE` and
`GUEST_STATE_ROOT`. These are **transport** settings, not application
deployment metadata.

`deployment-migrate-stage` never invokes the installer, restarts Redis or
enables Probot. An existing or partially staged private generation blocks a
second staging attempt; that state must be reconciled explicitly. The
five-role live activation gate remains separate and closed.

## Verify an existing staged migration (no restaging)

```sh
make -C local/fatline deployment-migrate-verify DEPLOYMENT=vm1
```

Agni stages its own exact source revision in nix.xd and invokes the
existing Nix-backed guest app with the named `migrate-verify` operation.
Unlike `deployment-migrate-stage`, it never runs application bundle
qualification or generates a new private candidate. The guest locates
**exactly one** existing migration generation under
`services/probot-migrations` and rejects absent/ambiguous selections.

The verifier checks the content-addressed original assessment,
unchanged legacy Quadlet hashes and Redis ACL, the five-role rendered
manifest, private credential file permissions, Redis ACL identity
preservation, all selected Nix executables and referenced store
closures, network/credential isolation, and the full systemd dependency
graph. It uses CoreOS's own Podman Quadlet generator with
`QUADLET_UNIT_DIRS=<staged rendered directory> ... --user --dryrun`
to validate translation without loading generated services. Finally,
it compares existing service invocation IDs before/after qualification.

Rollback preflight confirms that the original ACL and Quadlets remain
available; it **does not** qualify a live rollback. Activation remains
blocked until a separate controlled activation and tested restoration
path explicitly addresses RAM-only Redis data loss, application
readiness and GitHub App/ingress authority. A passing verification
never changes the installed profile or invokes systemctl reload/start.

## Plan activation without changing running services

```sh
make -C local/fatline deployment-migrate-activation-plan DEPLOYMENT=vm1
```

This operation reuses the one verified migration generation, validates
the exact Quadlets with the running guest's Quadlet generator, and stores
one private, immutable activation plan under
`services/activation-plans/<generation>/`. Its `plan.json` contains
source/target identities, boot and service invocation IDs, the
transition/readiness/rollback intent, and an explicit warning that
RAM-only Redis stream contents are **not** recoverable by config rollback.

The `rollback/` directory snapshots the original four Quadlets and
their drop-ins, network definition, ACL, Redis/Nginx configs, runtime
bootstrap template/script, and the original guest-private application
credentials. The copy remains on VM storage with private permissions;
values are not emitted in logs or placed in the Nix store. Plan creation
does not alter existing files or reload/restart systemd.

This is a **configuration rollback baseline**, not a tested rollback.
Activation and automated restoration remain unimplemented and blocked.
An existing plan is never silently replaced. If the VM's backing disk
can be discarded, the private backup must be durably protected before
a real activation; this development stage does not claim off-VM
recovery or Redis stream durability.

### Machine control boundary for later GCP orchestration

Agni owns desired application generation, per-guest verification,
activation readiness, and rollback semantics. The host-side
`operations/guest-migration.sh` currently uses nix.xd's local guest
transport for `starwisp`. Cloud orchestration should instead supply
a machine adapter resolving a GCP project/zone/instance identity and
remote execution credentials or guest-agent channel. A designated
Farcaster/controller can coordinate selection and authorization across
the planned multi-VM dual-stack subnet; no Agni operation should
require a Mac host or use a subnet address as durable VM identity.

For now **do not add a GCP API controller to the VM1 staging flow**.
Keep the guest-local Agni operation and its evidence format stable;
extract the transport and Nix-store visibility assumptions as concrete
adapters when the GCP deployment is implemented. The current CoreOS
guest implementation still specifically requires a read-only 9P Nix
store; that is not yet a GCP-qualified transport.
