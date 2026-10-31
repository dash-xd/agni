# Fatline Fedora CoreOS QEMU bootstrap

Nix-Alpine's `local/Makefile` is the supported entrypoint. It builds the pinned FCOS QEMU disk and Butane Ignition artifact, starts QEMU as a transient systemd-user service, and checks guest systemd and Podman through the serial log.

The profile in `butane/fatline-bootstrap.bu` refers to files under `resources/` with Butane `local` references. Set `COREOS_CONFIG_DIR` and `COREOS_RESOURCES` in Nix-Alpine Make to compose a workspace-owned Butane config and its local resource tree. The build copies both inputs into the Nix store, so edits produce a different artifact.

The old ISO/compose launcher at the parent directory is deprecated. It has mutable inputs and is not part of this qualification path.

## Host administration and service ownership

Fedora CoreOS provides the privileged `core` account by default. It has no default password or SSH key. System-level bootstrap units run as root to provision the guest, prepare user homes, and verify the qualification-user smoke. They do not run the Fatline application as root. Add a host-controlled SSH public key to the Ignition profile when SSH access is needed.

Podman and systemd are the runtime. The user-level Podman smoke runs inside the generated user's systemd manager with rootless Podman. The root bootstrap separately exercises Podman from a system transient unit. Container process identity remains an image and Quadlet configuration choice.

## Optional browser-console login

Nix-Alpine Make selects `fatline-bootstrap-console.bu` with `COREOS_QEMU_CONSOLE_LOGIN=1`. At each guest boot, a system service generates a random `<composition>-<hex>` account. Nix-Alpine's `COREOS_COMPOSITION_NAME` defaults to `COMPOSITION` (currently `fatline`), and its validated value is embedded in Ignition. The account prefix therefore tracks the selected composition, while the suffix remains unique for each boot. The account is unprivileged, has no `wheel` or `sudo` membership, and uses its Fedora CoreOS `/var/home/<user>` directory as its private workspace and home. The noVNC virtual terminal autologs into it through stock `agetty`, preserving Fedora's SELinux login transition.

The Ignition profile installs a user-level systemd service and enables it in that user's `default.target`. The generated account gets a lingering user manager, which runs the rootless Podman smoke and writes a completion marker under its runtime directory. The root bootstrap waits for that marker and reports the overall PASS only after both root bootstrap and user-level smoke succeed. This is the pattern for the later Fatline user Quadlets and services. `core` remains the root bootstrap identity for host-level setup.

The account can read files permitted by normal system permissions; root-owned credentials and protected files remain inaccessible. Its home is the writable application workspace. The headless/default profile does not create the console account or enable console autologin.

By default, the host qualification transient service stops after its smoke gate; its qcow2 overlay is removed during cleanup, so the generated account does not persist between runs. Set `COREOS_QEMU_HOLD=1` with web display and console login enabled to keep the guest open after the smoke passes. Stop it with `systemctl --user stop fatline-coreos-qemu-<scope>.service`, or let the configured qualification timeout expire.
