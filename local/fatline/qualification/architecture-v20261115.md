# Agni / Fatline composition authority — v20261115

Status: **migration candidate**, not live qualification or activation approval.
Selected from the earlier qualified branch
`cal/0.20261114.12-factory-live`. Zero-version CalVer branches may change
interfaces without compatibility. Runtime actions use immutable exact SHAs.

## One composition authority

`macOS bootstrap -> nix.xd provider/transport -> Nix-Alpine pinned Agni flake
-> Smoke composed executable -> Agni guest plan -> CoreOS systemd/Podman`.

Agni owns the machine/provider **topology**, Quadlet generation, role
dependencies, service ACLs, credential-mount contracts, and qualification
acceptance criteria for Fatline, Farcaster and Shoal. nix.xd must not
implement Agni's placements or application lifecycle in parallel. Smoke
owns GHXD and reusable Go action composition. Probot owns execution
fences, subscription semantics and webhook behavior.

An Agni flake selects exact Smoke/Probot source revisions and calls
reusable executables. A Makefile exposes stable names that select Nix
apps; it must not become a second stateful orchestrator. Prefer one generic
`make qualification QUALIFICATION=<name>` entrypoint, with thin
`check-deployment`, `deployment-...` compatibility aliases only until
their callers are removed.

## Canonical candidate contract

- **Source selection:** exact SHA (not mutable branch) and clean checkout.
  Nix-Alpine receives an immutable generation. Source seeding belongs
  to Smoke GHXD, with nix.xd providing generic transport only.
- **Build:** Nix flake owns its packages, derivations and environment.
  Bundle paths and source revision markers are verified structurally;
  only one machine-readable artifact-path record per key.
- **Deployment:** Agni's guest app validates source identity, rootless
  user, read-only host store mount, VM-local state and native
  systemd/Quadlet generator. No inline secrets.
- **Qualification:** static check, dependency closure, real isolated
  Redis/Skymill/Probot execution, fault/recovery, systemd lifecycle,
  explicit activation decision. Each gate has an exact pass/fail marker
  and source revision and must check unchanged baseline service IDs.
- **Cleanup:** all candidate processes, credentials and temporary
  files removed on either success or failure; no production failover
  or migration rollback requirements for the disposable Mac sandbox.

## Qualification semantics

The previously passed CoreOS generator dry-run proved four inert
subscription .container units plus a shared .network are loadable and
do not alter the original five VM1 systemd invocations. The pinned Probot
factory Node qualification passed 9/9. Those are **not** proof of live
two-subscription execution or independently supervised service restart.

The current live `factory-live` gate is pending. Do not mark it passed
until actual CoreOS evidence contains both normal factory and recovery
markers, a zero exit code, cleaned candidate and unchanged VM1 service
InvocationIDs.

Next, independently supervised systemd/Quadlet processors with disposable
state must pass SIGKILL/restart, pending Redis Streams reclamation,
idempotent effects and recovery while the unaffected subscription runs.
Only then may an Agni-specific activation target be considered.

## Explicit drift and retirement list

1. `operations/guest-migration.sh` is a 400-line host Bash dispatcher
   directly running `make` and `nix.xd project-host-run`. Its
   `seed-*-source` actions depend on Smoke's host Podman operator.
   **Transitional**, not canonical.
2. The giant `deployment-*` Makefile target catalog duplicates
   a generic Nix application selection interface. Keep previously
   passed gate names for evidence; new gates should use the
   `qualification` parameterized entrypoint. Do not add another
   application-specific operation to nix.xd.
3. `migrate-*`, rollback, recovery and compatibility snapshots remain
   historical sandbox tooling. Do not expand or gate new disposable
   Fatline candidates on those operations. Retire after explicit
   caller inventory.
4. Former one-off `processor`, `subscription`, and `factory`
   source artifact programs overlap. Consolidate them into a
   declarative source lock / single reusable Smoke materialization
   workflow **after** the live factory gate. Avoid another generation
   of literal-string validations.
5. The underlying CoreOS Starwisp service binding must be tied to
   immutable placement/VM identity if the topology is promoted; a
   static Shoal plan alone does not establish the running VM's identity.

## Full cutover acceptance

Do **not** report a completed architectural cleanup merely because a
static contract check passes. Required live evidence:
- Smoke GHXD can refresh and seed pinned sources using only the
  Nix-Alpine authority and pregranted volumes; macOS does not perform
  recurring GHXD Podman orchestration.
- nix.xd generic store/mounter/transport/rootless-UID and VM guest
  qualification pass, with a fully disposable host cleanup path.
- no new host-action/application-specific nix.xd callers; all active
  ones migrated and retired, or listed as outstanding blockers.
- final Fatline live factory + isolated OS process lifecycle gate pass.

Run `make -C local/fatline check-architecture` for the static policy check,
then `make -C local/fatline qualification QUALIFICATION=factory-live ...`
for the next **real** Fatline runtime gate. They are distinct.
