# CoreOS Fatline composition ownership

The development checkout is `agniYYYYMMDD`, on `vYYYYMMDD`. The branch is a mutable development locator, **not** a deployment input. To run a selected composition, resolve the Agni branch to a full commit SHA, stage that exact checkout, and record the SHA with the Nix lock, resulting store paths, guest boot ID and qualification evidence.

This migration declares `coreosPlans` internally and exposes standard read-only `coreos-plan-vm1` / `vm2` apps, corresponding packages, and the `checks.<system>.coreos-plan` derivation under `local/fatline`. The machine placement, transport, guest services, source revisions and compatibility pins now have an Agni-owned declaration. Existing runtime bundles (`coreos-services`, `host-link`, `startup-profile`) are reused, not rewritten.

The `nix.xd` runtime controllers now select this plan from a staged Agni checkout via `NIX_XD_COMPOSITION_FLAKE` and `NIX_XD_COMPOSITION_REV`. They verify the staged source revision, locked Nix-Alpine input, and selected Nix build output before guest mutation. The legacy `fatlinePlans` output is retained temporarily for compatibility auditing, but is no longer read by the CoreOS/Fatline VM, host-link, or application-service controllers. Full flake-owned lifecycle orchestration and guest qualification remain outstanding.

## Inspect the read-only plan

From the dated `nix.xd` workspace, with a running Nix-Alpine owner, stage the dated Agni checkout:

```sh
make stage PROVIDER=podman SCOPE=nix-xd-arm WORKSPACES="$HOME/workspace" CHECKOUT=agni20261111
make run PROVIDER=podman SCOPE=nix-xd-arm \
  FLAKE=agni20261111/local/fatline TARGET='#coreos-plan-vm1'
```

The output must identify `sourceSelection.mutableBranchAllowed=false` and full 40-hex-character immutable component revisions. The dated branch is recorded by the invocation/evidence layer, not hardcoded into an immutable composition flake; a branch alone must never be passed as the final runtime source identity.

Local Nix flake validation (in the Agni dated checkout, if Nix is installed):

```sh
nix build --no-link --no-update-lock-file ./local/fatline#checks.aarch64-linux.coreos-plan
nix build --no-link --no-update-lock-file ./local/fatline#coreos-plan-vm1
```

The existing `nix.xd` Makefile's `run` and `stage` are generic; this step needs no Fatline-specific Make target.

## Qualification order

1. Validate the dated branch and immutable source selection (including commit and lock identity). The Nix-Alpine runtime input is committed to the Fatline flake lock.
2. Build the Agni-owned service and machine artifacts, pin GC roots, and inspect generated systemd-user/Quadlets.
3. Migrate the generic CoreOS adapter to consume the resolved Agni plan rather than its built-in Fatline plan.
4. Activate in the disposable CoreOS guest and check boot identity, `systemctl --user`, Podman service state, readiness, ACL segregation, Logma/Skymill integration, and recovery.
5. Record immutable revisions, store closure paths, build outputs and guest evidence. Release tagging happens only after the full gate passes.

`fullFatlineQualified = false` until the guest integration gate passes. Neither these plan outputs nor the prior Podman Machine storage isolation test establish guest Fatline qualification.

## Host-side immutable preflight

From the dated `nix.xd` controller, stage both the committed `nix.xd` and Agni checkouts into the Nix-Alpine owner, then use the thin Makefile adapter:

```sh
make agni-coreos-plan-check PROVIDER=podman SCOPE=nix-xd-arm \
  COMPOSITION_FLAKE=/workspaces/agni20261111/local/fatline \
  COMPOSITION_REV="$(git -C "$HOME/workspace/agni20261111" rev-parse HEAD)"
```

The preflight builds only the plan JSON, not the Fatline images or guest services. It writes `.state/agni-coreos/vm1-selection.json` under the controller checkout, recording the exact Agni commit, plan store output, SHA-256 of plan and lock, Nix-Alpine runtime pin, and component revision pins (Logma, Skymill, Ratelimiter and service bundles). A mismatch fails before any guest mutation.

The existing `fatline-vm-local` invokes this preflight before starting the guest. Previous generations from the legacy controller remain protected; an existing scope with a different composition manifest requires explicit migration or a fresh sandbox. No automatic replacement is performed.

## Agni-owned host tool artifacts

A Fatline plan can declare `hostArtifacts.smoke`, including an exact-revision flake, an app output, the pinned Smoke source revision, and its expected host target. The current candidate uses `#smoke-host-artifact` to cross-compile `cmd/smoke-wisp` for Darwin ARM64 from a Nix-fetched exact Smoke revision. The app places the output in the owner's Nix store, retains a GC root and reports its SHA-256. The generic Nix-Alpine/host transport verifies the bytes before making the executable available to the host-side qualifier.

This app deliberately performs Go module downloads and build effects **at runtime**. It is not yet a fixed-output, hermetically vendored derivation. Pinning source and module checksums plus recording the resulting binary hash enables qualification, but do not conflate that with binary reproducibility. Move vendoring into the Nix build graph after the first runtime gate passes.

The existing `nix.xd` Fatline-specific controllers remain compatibility code during the ongoing VM1 qualification. Their application phase graph must be migrated to Agni before retiring the older controller targets; the generic `nix.xd` Make interface is `stage`, `run`, `build`, and artifact transport.

## Host action dispatch

Host effects are selected by the generic Nix-Alpine Make entry point, not by project-named targets:

```sh
make project-host-run PROJECT=agni20261111 APPLICATION=fatline ACTION=resource-qualify \
  COMPOSITION_FLAKE=/workspaces/agni20261111/local/fatline \
  COMPOSITION_REV=5442e5f9b13479edefb55cfa3c3cd518e199ad5c
```

The general host dispatcher identifies the committed project and executes `local/fatline/host-actions/resource-qualify.sh`. The Agni action selects its exact pinned Smoke host-artifact app, while the running legacy composition stays pinned and unchanged. This is a compatibility host action until its resource qualification controller is fully migrated out of `nix.xd`.

## Nix-Alpine-native qualification and runtime file capabilities

Agni now exposes `#resource-preflight` as a Linux-executed Nix flake app. It builds the pinned Smoke `cmd/smoke-wisp` entry point natively within Nix-Alpine, retains the executable in the existing owner store, and records its source revision and digest. An optional `--check-transport` phase requires explicit guest address, port, mounted SSH identity, and known-hosts file; it fails before claiming transport success if any capability is missing. Neither phase claims Logma resource qualification: publication, ACL denials, delivery, and cleanup remain separate unqualified gates.

The generic infrastructure now allows optional scoped named volumes under `/run/nix-xd/mounts/<alias>`, either read-only or explicitly writable. The Nix store remains separately managed. Credentials should be exposed only to the chosen qualification scope, and host-to-Podman/Podman-to-CoreOS file shares must be declared separately, with verified ownership and access. Existing Quadlets cannot gain new mounts without a controlled recreation; do not retrofit them by editing the active VM1 state.

Run preflight from `nix.xd` with the generic `make run FLAKE=agni20261111/local/fatline TARGET='#resource-preflight'` interface after staging Agni. The older host-side resource qualification remains a compatibility path pending the native credential and guest network binding.

## Selected runtime state-volume grants

`qualification/runtime-grants.json` is the non-secret storage grant declaration for the Linux-side qualifier. It selects two **future bindings**, not existing VM1 credentials or disks:

- A read-only **non-secret** qualification input volume `nix-xd-state-control-fatline-input`, written by a separate `fatline-controller` principal
- A writable qualification-evidence volume `nix-xd-state-control-qualification`, whose designated writer is the Nix-Alpine runtime `nix-xd-arm`

Both use paths under `/run/nix-xd/mounts`; no Nix store is shared writable and the declaration contains no credential material. The generic `nix.xd` `grants-plan`, `grants-render`, and `grants-verify` commands validate and inspect this declaration. Provisioning alone creates **empty** volumes; it does not migrate host credentials. **Do not put SSH keys, Redis passwords, or plaintext application secrets into these long-lived owner mounts.** Private credentials require a separate short-lived qualifier with explicit per-run grants. Do not apply these grants to the active runtime until the guest transport, access identities, and credential handoff have been reconciled. CoreOS's existing 9P store export is independent and read-only.

The native Smoke preflight is already qualified; full Logma resource dispatch and evidence writing via these mounts remain unqualified.

## Shared secret volumes (isolated qualifier)

The **same Podman named-volume system** manages Nix stores, chroot stores, SOPS/age secret stores, input data and evidence. There is no required credential copy or separate secret transport. `qualification/isolated-runtime-grants.json` selects a future dedicated `fatline-qualifier` runtime with three grants: `nix-xd-state-secret-fatline:ro`, `nix-xd-state-control-fatline-input:ro`, and `nix-xd-state-control-fatline-evidence:rw`. The flake exposes this declaration as `#isolated-runtime-grants`. These are logical, opt-in declarations; the isolated container and volumes have not been provisioned or runtime-qualified.

Encrypted SOPS data and age private identities can persist on a dedicated secret volume. Linux UID/GID ownership, mode/ACL, Podman user namespaces, and SELinux confinement where available determine which consumer may open each file. The ro mount prevents mutation by the selected consumer but does not enforce privilege separation between programs sharing that consumer's namespace. Avoid exposing the secret volume to the long-lived general-purpose Nix-Alpine builder unless all its workloads are trusted for that credential.

The VM1 9P path is already qualified for the shared Nix store, **not** for arbitrary data/secret exports. QEMU 9P permissions must be qualified independently with guest identity mapping, and SELinux enforcement in the Podman Machine should not be assumed to carry into CoreOS. No VM1 disk, container, credentials or service needs changing for grant declaration checks.

## Isolated Podman and read-only CoreOS 9P gates

Before using persistent Fatline resources, run the generic `make grants-isolation-qualify` gate in `nix.xd`. It creates only **disposable, non-secret** local fixture volumes under the selected rootless Podman Machine, verifies an authorized matching UID/GID mapping can read the private fixture and write evidence, verifies an unrelated mapping cannot read it, and removes the fixture. Its SELinux prerequisite and fixture ownership are the same class of primitives exercised by the existing tenant-storage gate. The private fixture is not a real age identity.

`qualification/guest-9p-grants.json` declares the read-only `fatlineinput` QEMU 9P tag for a separately provisioned CoreOS guest. It intentionally excludes live secrets. The generic `guest-9p-plan` and `guest-9p-preflight` verify the declaration and existing state-volume labels. `COREOS_9P_GRANTS_FILE` may be supplied when **creating** a new QEMU runner; it is not an in-place configuration mechanism for VM1. CoreOS guest mount/unit construction and guest-side identity checks remain unqualified. Retain VM1's current runner and data unchanged.

Full native Logma resource dispatch, Redis ACL failure modes, and recovery gates still require the guest-side access and authenticated SSH/Redis transport bindings before `#resource-qualify` should be marked passed.
