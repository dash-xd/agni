# Fatline Fedora CoreOS QEMU bootstrap

Nix-Alpine's `local/Makefile` is the supported entrypoint. It builds the pinned FCOS QEMU disk and Butane Ignition artifact, starts QEMU as a transient systemd-user service, and checks the guest's transient Podman bootstrap unit through the serial log.

The profile in `butane/fatline-bootstrap.bu` refers to files under `resources/` with Butane `local` references. Set `COREOS_CONFIG_DIR` and `COREOS_RESOURCES` in Nix-Alpine Make to compose a workspace-owned Butane config and its local resource tree. The build copies both inputs into the Nix store, so edits produce a different artifact.

The old ISO/compose launcher at the parent directory is deprecated. It has mutable inputs and is not part of this qualification path.

## Optional browser-console login

The Nix-Alpine Make target can select the `fatline-bootstrap-console.bu` profile with `COREOS_QEMU_CONSOLE_LOGIN=1`. On each boot, a systemd service creates a unique `fatline-<random>` account in the guest and the noVNC virtual terminal autologs into that account. It is a passwordless, wheel-group account intended only for this disposable local QEMU qualification guest; the host publishes noVNC only on loopback. SSH keys are not configured.

The headless/default profile does not create this account or enable console autologin. By default, the qualification transient service stops after its smoke gate; its qcow2 overlay is removed during cleanup, so the generated account does not persist between runs. Set `COREOS_QEMU_HOLD=1` with console login enabled to keep the guest open after the smoke passes. Stop it with `systemctl --user stop fatline-coreos-qemu-<scope>.service`, or let the configured qualification timeout expire.
