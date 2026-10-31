# Fatline Fedora CoreOS QEMU bootstrap

Nix-Alpine's `local/Makefile` is the supported entrypoint. It builds the pinned FCOS QEMU disk and Butane Ignition artifact, starts QEMU as a transient systemd-user service, and checks the guest's transient Podman bootstrap unit through the serial log.

The profile in `butane/fatline-bootstrap.bu` refers to files under `resources/` with Butane `local` references. Set `COREOS_CONFIG_DIR` and `COREOS_RESOURCES` in Nix-Alpine Make to compose a workspace-owned Butane config and its local resource tree. The build copies both inputs into the Nix store, so edits produce a different artifact.

The old ISO/compose launcher at the parent directory is deprecated. It has mutable inputs and is not part of this qualification path.

## Optional browser-console login

The Nix-Alpine Make target can select the `fatline-bootstrap-console.bu` profile with `COREOS_QEMU_CONSOLE_LOGIN=1`. It autologs the built-in `core` user onto the guest's virtual terminal so the noVNC console lands at a shell. This profile is intended for a disposable local QEMU qualification guest; the host publishes noVNC only on loopback. It does not configure SSH keys or a password, and the profile should not be used for a network-exposed or persistent guest.

The headless/default profile does not enable console autologin. The qualification transient service is stopped and cleaned up when its gate completes.
