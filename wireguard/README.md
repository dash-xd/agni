# Fedora CoreOS WireGuard egress gateway

This is an opt-in **Fedora CoreOS host WireGuard** service, independent of Squid, Podman, and Fatline. It does not alter existing GCP Terraform resources or deploy automatically.

## Network prerequisites

- A reachable public UDP endpoint on port 51820. IAP TCP forwarding is **not** a WireGuard UDP endpoint.
- Explicit GCP VPC ingress firewall rule, scoped to intended client public source CIDRs. Do not use 0.0.0.0/0 by default.
- An outbound internet path from the CoreOS VM (external IPv4 or suitable NAT); confirm the actual egress IP.
- Choose a tunnel subnet that does not overlap local, VPC, or destination networks.
- Fedora CoreOS normally uses NetworkManager. Use NetworkManager-managed WireGuard connections; do not start systemd-networkd alongside the existing network manager.

## Keys

Generate one server key and one unique key per client **off-repository** using `wg genkey` and `wg pubkey`. Do not place private keys in Git, Nix store derivations, Terraform variables/state, Ignition user-data, or GCE instance metadata. Copy the server private key to the host using an authenticated secret delivery mechanism. Provisioning private keys is deliberately separate from this repository.

## Host deployment

The earlier `50-wg-minecraft.netdev.example` and `.network.example` files are **superseded design references**, not deployable Fedora CoreOS configuration. Do not install them on a NetworkManager-managed host. Generate unique keys outside Git, provision the server private key securely, and import the WireGuard configuration using NetworkManager (`nmcli connection import type wireguard file ...`) after checking that the installed NetworkManager version supports this import. Ensure the resulting connection autoconnects and persists across reboot. IP forwarding and narrowly scoped NAT require separate qualified host firewall configuration; the QEMU user-network UDP port mapping alone does not prove internet egress routing.

## Client profile

See `client.conf.example`. Replace keys, public endpoint and DNS settings; import into official WireGuard clients on Windows, macOS or Linux. `AllowedIPs=0.0.0.0/0` routes all IPv4 traffic through the gateway, not only Minecraft. This is the simplest cross-platform leak-resistant choice for Minecraft TCP; it also increases VM egress. IPv6 is **not** tunneled by this example. To prevent bypass on dual-stack Minecraft destinations, disable IPv6 for the client session or implement and test an IPv6 tunnel and egress policy. Do not treat the example as an IPv6 kill switch.

## Qualification

1. Confirm VPC firewall permits UDP 51820 only from intended client source ranges, and that the server has a public UDP endpoint.
2. Validate NetworkManager WireGuard import, `nmcli connection show`, and `journalctl -u NetworkManager`; ensure systemd-networkd is not competing for the interface.
3. Import a unique client profile, activate the tunnel, and verify handshake counters (using `wg show` where installed).
4. Check a public IPv4 egress service from the client and compare with the VM's observed public egress address. Confirm Minecraft's TCP connection uses the tunnel.
5. Test DNS resolution and IPv6 behavior explicitly; a public-IP check alone does not prove absence of DNS/IPv6 leaks.
6. Reboot a disposable VM and verify NetworkManager restores the interface and forwarding/NAT without manual intervention.
7. Test client disconnect, unauthorized key rejection, peer isolation, and routing rollback.

No successful runtime qualification is claimed by these templates.
