# Local QEMU/KVM qualification (ThinkPad)

This opt-in runner uses the existing Agni `qemu/coreos-live/` directory, but no privileged QEMU container or Compose. It does not alter GCE resources.

## Inputs

Acquire a specific Fedora CoreOS **QEMU qcow2** artifact from the official release stream, record the exact version and checksum, and verify its SHA-256 before using it. Obtain a compatible Ignition JSON configuration rendered with Butane. Do not use an ISO as a persistent disk. Do not embed secrets in the Ignition file.

The local runner is defined in `flake.local.nix` to avoid breaking the existing legacy flake until artifact pinning is reconciled. Nix does not currently fetch or pin the CoreOS image; this is an outstanding gate.

## Run

```sh
cd qemu/coreos-live
export AGNI_COREOS_QCOW2=/absolute/path/to/verified-coreos.qcow2
export AGNI_IGNITION=/absolute/path/to/config.ign
nix shell nixpkgs#qemu nixpkgs#systemd --command bash deploy-local.sh install
```

The staged `flake.local.nix` is not yet wired into the canonical flake; use the command above or run the script directly with QEMU installed on the host:

```sh
bash deploy-local.sh install
bash deploy-local.sh status
```

The installer copies the image into a persistent user state directory and installs a user systemd unit. It refuses to overwrite an existing guest disk or replace first-boot Ignition. SSH maps to localhost:2222 and WireGuard UDP to localhost:51820. QEMU user networking is suitable for initial handshake testing but is **not** a realistic public VPN gateway or a reliable test of forwarded-client internet egress/NAT. That requires a tap/bridge network with host firewall and routing validation.

Host reboot persistence additionally requires user lingering (`loginctl enable-linger`) or an active login session. Do not enable lingering without an explicit operational decision.

## Gates

1. Verify the CoreOS artifact checksum and Ignition syntax.
2. Start QEMU and confirm SSH, persistent disk and reboot recovery.
3. Provision a NetworkManager-managed WireGuard interface inside the guest; never enable systemd-networkd in parallel.
4. Test loopback-forwarded UDP handshake and peer isolation.
5. Move to a bridged/tap qualification topology to test routed egress, NAT and DNS.
6. Only after those gates, design GCE public UDP endpoint and firewall integration.

No local execution or runtime qualification has been performed.
