# Fatline Fedora CoreOS QEMU bootstrap

Nix-Alpine's `local/Makefile` is the supported entrypoint. It builds the pinned FCOS QEMU disk and Butane Ignition artifact, starts QEMU as a transient systemd-user service, and checks the guest's transient Podman bootstrap unit through the serial log.

The profile in `butane/fatline-bootstrap.bu` refers to files under `resources/` with Butane `local` references. Set `COREOS_CONFIG_DIR` and `COREOS_RESOURCES` in Nix-Alpine Make to compose a workspace-owned Butane config and its local resource tree. The build copies both inputs into the Nix store, so edits produce a different artifact.

The old ISO/compose launcher at the parent directory is deprecated. It has mutable inputs and is not part of this qualification path.
