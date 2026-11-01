# Fatline Fedora CoreOS QEMU bootstrap

Nix-Alpine's `local/Makefile` is the supported entrypoint. It builds the pinned FCOS QEMU disk and Butane Ignition artifact, starts QEMU in a host transient systemd-user service, and checks root bootstrap, the generated composition account's rootless systemd/Podman smoke, and (when enabled) the local console account's read-only workspace boundary through the serial log.

The profile in `butane/fatline-bootstrap.bu` refers to files under `resources/` with Butane `local` references. Set `COREOS_CONFIG_DIR` and `COREOS_RESOURCES` in Nix-Alpine Make to compose a workspace-owned Butane config and its local resource tree. The build copies both inputs into the Nix store, so edits produce a different artifact.

The old ISO/compose launcher at the parent directory is deprecated. It has mutable inputs and is not part of this qualification path.

## Host administration and service ownership

Fedora CoreOS provides the privileged `core` account by default. It has no default password or SSH key. System-level bootstrap units run as root to provision the guest, prepare user homes, and verify the qualification smokes. They do not run the Fatline application as root. Add a host-controlled SSH public key to the Ignition profile when SSH access is needed.

Podman and systemd are the runtime. The host QEMU process runs in a transient systemd-user service. Inside CoreOS, a system unit runs the root bootstrap Podman check and waits for the generated composition account's enabled systemd unit to complete a rootless Podman check. This avoids starting a second system-manager job from inside a boot service. Fatline application Quadlets belong in the composition account's systemd manager. The application account uses `/usr/sbin/nologin`, has no interactive console login, and receives only the app-specific user-unit skeleton. Container process identity remains an image and Quadlet configuration choice.

## Optional browser-console login

Nix-Alpine Make selects `fatline-bootstrap-console.bu` with `COREOS_QEMU_CONSOLE_LOGIN=1`. At each guest boot, the Ignition bootstrap generates two independent random identities:

- `<composition>-<12 hex>` is the noninteractive app/service account. Its private `/var/home/<user>` is the rootless Podman/systemd workspace; it has no `wheel` or `sudo` membership and gets a lingering user manager for application Quadlets.
- `local-<12 hex>` is the separate unprivileged console login. The noVNC virtual terminal autologs into it through stock `agetty`, preserving Fedora's SELinux login transition. It has no `wheel` or `sudo` membership.

The console account's interactive login shell is re-executed inside a user systemd service with `ProtectSystem=strict`. The service allows writes only to that account's home/workspace, and hides its runtime directory (including user-manager control sockets) from the shell. Its startup check confirms the workspace is writable and `/var/tmp` is read-only; the root bootstrap reports overall success only after this check and the composition account's rootless Podman smoke pass. This is a boundary for the interactive console session; the local account should not be used to run Fatline application services.

Ordinary filesystem read permissions apply: system-readable files are readable, while root-only files and credentials remain protected. The generated user's own workspace is private. The headless/default profile does not create either generated account or enable console autologin.

By default, the host qualification transient service stops after its smoke gate; its qcow2 overlay is removed during cleanup, so the generated accounts do not persist between runs. Set `COREOS_QEMU_HOLD=1` with web display and console login enabled to keep the guest open after the smoke passes. Stop it with `systemctl --user stop fatline-coreos-qemu-<scope>.service`, or let the configured qualification timeout expire.
