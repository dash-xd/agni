# Fatline Fedora CoreOS QEMU bootstrap

Nix-Alpine's `local/Makefile` is the supported entrypoint. It builds the pinned FCOS QEMU disk and Butane Ignition artifact, starts QEMU as a transient systemd-user service, and checks the guest's transient Podman bootstrap unit through the serial log.

The profile in `butane/fatline-bootstrap.bu` refers to files under `resources/` with Butane `local` references. Set `COREOS_CONFIG_DIR` and `COREOS_RESOURCES` in Nix-Alpine Make to compose a workspace-owned Butane config and its local resource tree. The build copies both inputs into the Nix store, so edits produce a different artifact.

The old ISO/compose launcher at the parent directory is deprecated. It has mutable inputs and is not part of this qualification path.

## Host administration and service ownership

Fedora CoreOS provides the privileged `core` account by default. It has no default password or SSH key. The bootstrap is a system-level systemd unit and runs as root; it does not depend on the console account or run application containers as root. Add a host-controlled SSH public key to the Ignition profile when SSH access is needed.

Keep host setup in root-owned systemd units. Run application containers as non-root where their image and port configuration allow it. Podman's host-side privilege model and the process identity inside each container are separate settings and should be qualified separately.

## Optional browser-console login

Nix-Alpine Make selects `fatline-bootstrap-console.bu` with `COREOS_QEMU_CONSOLE_LOGIN=1`. At each guest boot, a systemd service generates a random `fatline-<hex>` account. The account is unprivileged, has no `wheel` or `sudo` membership, and uses its standard Fedora CoreOS `/var/home/<user>` directory as its private workspace and home. Creating the home with `useradd --create-home` gives it the expected ownership and SELinux home label. The noVNC virtual terminal autologs into it. The qualification guest has no SSH key configured by this profile.

The account can read files permitted by their normal system permissions. Root-owned credentials and other protected files stay inaccessible; do not grant a global read ACL over the guest filesystem because that would expose secrets. The home directory is the account's persistent writable workspace. Standard ephemeral runtime locations such as the guest's temporary filesystem may also be writable.

The headless/default profile does not create the console account or enable console autologin. By default, the qualification transient service stops after its smoke gate; its qcow2 overlay is removed during cleanup, so the generated account does not persist between runs. Set `COREOS_QEMU_HOLD=1` with console login enabled to keep the guest open after the smoke passes. Stop it with `systemctl --user stop fatline-coreos-qemu-<scope>.service`, or let the configured qualification timeout expire.
