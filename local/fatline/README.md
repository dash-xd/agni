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

## Activation preflight (read-only, does not authorize cutover)

After the private activation plan has been prepared on VM1, run:

```sh
make -C local/fatline deployment-migrate-activation-check DEPLOYMENT=vm1
```

The workflow reuses the exact existing guest generation and private
activation-plan directory. It first reruns the five-role static and
Podman Quadlet generator checks, then verifies each snapshotted legacy
Quadlet/network/config/credential against its SHA-256 and current live
counterpart, the guest boot ID and the four systemd invocation IDs,
the original assessment and staged target ACL, and visibility of legacy
Nix store executables. No new artifact candidate or activation plan is
created, and no service is stopped or restarted. A subsequent reboot,
service restart or baseline change fails closed rather than silently
reusing stale authorization evidence.

`AGNI_ACTIVATION_CHECK=passed` means the **baseline was verified**,
not that activation is permitted. The check still reports
`readiness=blocked activation=blocked` and explicitly lists unresolved
gates: live application readiness, GitHub App/ingress binding, a tested
rollback executor, retention of legacy store roots, and operator
acknowledgement of Redis RAM-only stream loss.

`make -C local/fatline deployment-migrate-activate DEPLOYMENT=vm1`
is present as a deliberately fail-closed interface. There is no
functional live cutover behind this command yet. An activation executor
must not reuse the read-only preflight as blanket approval or claim
Redis in-memory data would be restored by configuration rollback.

## Isolated legacy recovery qualification

```sh
make -C local/fatline deployment-migrate-recovery-qualify DEPLOYMENT=vm1
```

This read-only operation reuses the existing VM1 private activation plan and
five-role candidate. It first runs `activation-check` to detect source
drift. Inside an isolated, ephemeral workspace on CoreOS, it restores
the saved legacy four-role Quadlets, network, configs, and private
credentials from their checksum-verified snapshot. It validates the
reconstructed four-role systemd dependencies and invokes the VM's
Podman Quadlet generator with `--user --dryrun` against **only** the
restored units. The temporary recovered files are removed when the
operation ends, and the existing service invocation IDs are compared
before/after.

This gate does not install Quadlets, reload systemd, restart Redis,
perform an actual rollback, or claim that the old application processes
will pass runtime readiness. It verifies **config restoration and
generator acceptance** only.

The gate also rechecks **visibility** of original Nix executables,
but VM1 has a read-only guest mount of its Nix-Alpine owner's store.
Only the store owner can attest that roots for the old closures are
protected against garbage collection. Accordingly, the result
explicitly reports `root_retention=unverified`; a separate
owner-side GC-root retention receipt is still required before
destructive activation. Redis remains RAM-only and in-memory stream
contents are not recoverable through this restoration procedure.

For GCP/Farcaster, this remains a guest-local Agni application gate.
Farcaster may later acquire the owner-side store retention receipt
and invoke these same guest checks via a GCP machine/guest adapter;
nothing here assumes a Mac host or claims to control nested CoreOS
instances through the GCE API.

## Local disposable VM1 activation (explicitly not production)

The five-role candidate can be installed using the existing Agni startup-profile
installer after the immutable migration, activation-plan, and baseline gates have
passed. The sandbox action invokes the existing isolated recovery qualification
before the cutover; it does **not** duplicate the installer, reset the CoreOS VM,
or touch World 1. Only VM1's application services are stopped/restarted.

The operator must explicitly acknowledge that Redis is RAM-only and loses its
current data on restart:

```sh
make -C local/fatline deployment-migrate-activation-plan DEPLOYMENT=vm1
make -C local/fatline deployment-migrate-activate-sandbox DEPLOYMENT=vm1 \\
  REDIS_DATA_LOSS_ACK=DISCARD-VM1-REDIS-MEMORY
```

The sandbox path verifies the plan's source/boot/invocation fingerprints,
private snapshot and original store visibility, performs the isolated legacy
recovery gate, then calls the already-existing `runtime.sh install-probot`
with the selected rendered generation. It checks user-systemd/Podman status,
read-only store/credential mounts, Redis bootstrap revocation and records the
active generation. If installation fails, the target is **not** reported as
qualified; automatic rollback is not implemented and must not be assumed.

This is a rootless guest application operation. Neither Redis's bootstrap ACL
principal nor a Linux root user is an ongoing application identity. The Nix
store owner builds and retains closures; the CoreOS `wisp` systemd user manages
rootless Podman containers; each service authenticates to Redis with its own
ACL principal. Redis is configured with one logical database (DB 0); separation
comes from ACL commands, key prefixes, channel patterns and private credentials,
not Redis DB numbers. Prajapati's tenant registry is a caller authorization
contract, not a substitute for Redis ACL isolation.

The Probot worker remains disabled in the selected manifest and no GitHub App
installation/ingress authority is installed by this action. A passing sandbox
activation establishes local startup and bootstrap revocation only; webhook
settlement, cross-tenant adversarial ACL denial, and World 1 integration remain
separate gates. Production `deployment-migrate-activate` remains blocked.

## Recover a partially activated disposable Skymill HTTP credential

If a sandbox cutover installed the five-role profile but timed out because
Skymill rejected a newline-terminated bearer credential, use
`make -C local/fatline deployment-recover-sandbox-http DEPLOYMENT=vm1`.
This is not a migration restage or a Redis restart. The operation requires
exactly one staged generation and an installed manifest matching it, checks
that Skymill and Probot share the same private 64-hex token, atomically removes
only its trailing LF in the two installed credential files, restarts Skymill
and Probot, checks stabilized five-role status and Redis bootstrap revocation.
It does not alter the staged private generation, redis credentials, ACLs,
VM topology, or activate GitHub ingress. A failure remains unqualified and
is reported without claiming recovery or rollback. New candidate generations
write these bearer token files without a trailing newline.

The repair helper runs through rootless Podman with the guest 9P store
mounted at `/nix/store` inside its isolated container. Running the
Nix-pinned interpreter directly on CoreOS is incorrect: the host's store
mount is `/var/mnt/nixstore`. This update does not change the selected
application generation or restart Redis.

## Live, non-restarting VM1 runtime gate

Run `make -C local/fatline deployment-qualify-runtime DEPLOYMENT=vm1`
from the version-pinned Nix-Alpine owner workflow. This target checks the
already activated generation and all five user-systemd service invocations,
validates legacy Logma/Skymill ACL denials against live Redis with the pinned
Go probe, tests Logma's strict HTTP readiness and Probot's local HTTP/router
authentication, and exercises the **current** Skymill HTTP bearer API using
an isolated synthetic message. It checks publish-once idempotency, opaque
provider delivery IDs, NACK acceptance and ACK state cleanup. It does not
assert a completed NACK retry/redelivery (the current Redis provider reclaims
idle pending entries separately), a genuine GitHub App webhook, the disabled
Probot worker, or every adversarial tenant boundary. It never restarts Redis,
installs Quadlets or modifies credentials; the synthetic stream fixture and
idempotency key are the intended ephemeral Redis changes. The Skymill gate
fails closed if consumer group pending deliveries exist rather than ACKing
unknown application messages.

## Interactive macOS shell safety

For interactive zsh, never paste `set -e`, `set -o errexit`,
`exec <command>`, `source operations/guest-migration.sh`, or
`source bin/nix-xd-log` as part of a copy/paste qualification recipe.
Shell option changes made at the prompt persist into later commands;
particularly, `set -e` may terminate the interactive shell when a
subsequent command fails. Scripts may use strict mode **inside their own
child Bash processes**, because those options cannot propagate to the
parent zsh session.

The intended operator invocation is one ordinary command, without a
preceding shell-mode change:

```sh
cd ~/workspace/nix.xd20261113.0
NIX_XD_LOG_DIR="$HOME/.local/nix.xd/logs" NIX_XD_MACHINE=coreos-arm64 \
  bash bin/nix-xd-log nix-xd-arm fatline-qualify-runtime \
  make -C ../agni20261113.0/local/fatline deployment-qualify-runtime \
    DEPLOYMENT=vm1 NIX_XD_DIR="$PWD" PROVIDER=podman MACHINE=coreos-arm64
```

The command returns its exit code and a log path and **must not**
replace the user's interactive shell. On a zsh session where an earlier
pasted recipe enabled `errexit`, first run `unsetopt ERR_EXIT`
(or `set +e`). This shell setting is unrelated to whether an
Agni qualification succeeds. The message `[Process completed]`
comes from the terminal session after its foreground process exits;
if it also appears after a successful ordinary shell command, check
the Terminal profile's shell startup command and any one-shot launcher.

## Read-only runtime network diagnosis

`deployment-diagnose-runtime-network` runs against the *already deployed*
VM1 generation and reports systemd active states, container status and
TCP/DNS results from an isolated rootless container on the actual Fatline
network. It checks the pinned service endpoints: logma:8080,
skymill:8081, probot:3000, and redis-proxy:6379. It does not authenticate,
read secrets, restart units, or write Redis data. The target returns
`AGNI_RUNTIME_NETWORK=observed changes=none` even if an endpoint is
unreachable; inspect `AGNI_NETWORK_ENDPOINT` lines for the actual failure.

Network diagnosis now also captures Logma's process and TCP listening
sockets, plus a bounded allowlist of diagnostic startup messages. It never
reads service environment values or credential files and does not change
systemd or Podman state.

The diagnostic probes both `logma:8080` (declared contract) and
`logma:18081` (the unexpected observed listener) and fetches
`/lifecycle/readyz` on each without authentication or mutation. A
successful TCP connection alone does not establish Logma HTTP readiness.
