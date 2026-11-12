# CoreOS Fatline composition ownership

The development checkout is `agniYYYYMMDD`, on `vYYYYMMDD`. The branch is a mutable development locator, **not** a deployment input. To run a selected composition, resolve the Agni branch to a full commit SHA, stage that exact checkout, and record the SHA with the Nix lock, resulting store paths, guest boot ID and qualification evidence.

This initial migration adds `coreosPlans.<system>.vm1` / `vm2` and read-only `coreos-plan-vm1` / `vm2` apps under `local/fatline`. The machine placement, transport, guest services, source revisions and compatibility pins now have an Agni-owned declaration. Existing runtime bundles (`coreos-services`, `host-link`, `startup-profile`) are reused, not rewritten.

The `nix.xd` copy of `compositions/fatline-coreos.nix` remains temporarily because its existing host runtime controllers consume it. It is **legacy compatibility**, not an independent source of truth to update. The subsequent adapter change must read the Agni plan and compare the selected SHA and plan digest before making guest mutations; then remove the hard-coded `fatlinePlans` from `nix.xd`. Until then, do not claim the Fatline runtime is flake-orchestrated by Agni.

## Inspect the read-only plan

From the dated `nix.xd` workspace, with a running Nix-Alpine owner, stage the dated Agni checkout:

```sh
make stage PROVIDER=podman SCOPE=nix-xd-arm WORKSPACES="$HOME/workspace" CHECKOUT=agni20261111
make run PROVIDER=podman SCOPE=nix-xd-arm \
  FLAKE=agni20261111/local/fatline TARGET='#coreos-plan-vm1'
```

The output must identify `sourceSelection.developmentBranch=v20261111` and full 40-hex-character immutable component revisions. A branch alone must never be passed as the final runtime source identity.

Local Nix flake validation (in the Agni dated checkout, if Nix is installed):

```sh
nix flake check ./local/fatline --no-write-lock-file
nix eval --json ./local/fatline#coreosPlans.aarch64-linux.vm1
```

The existing `nix.xd` Makefile's `run` and `stage` are generic; this step needs no Fatline-specific Make target.

## Qualification order

1. Validate the dated branch and immutable source selection (including commit and lock identity).
2. Build the Agni-owned service and machine artifacts, pin GC roots, and inspect generated systemd-user/Quadlets.
3. Migrate the generic CoreOS adapter to consume the resolved Agni plan rather than its built-in Fatline plan.
4. Activate in the disposable CoreOS guest and check boot identity, `systemctl --user`, Podman service state, readiness, ACL segregation, Logma/Skymill integration, and recovery.
5. Record immutable revisions, store closure paths, build outputs and guest evidence. Release tagging happens only after the full gate passes.

`fullFatlineQualified = false` until the guest integration gate passes. Neither these plan outputs nor the prior Podman Machine storage isolation test establish guest Fatline qualification.
