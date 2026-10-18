# Fedora CoreOS WireGuard egress gateway

This is an opt-in **host systemd-networkd** service, independent of Squid, Podman, and Fatline. It does not alter existing GCP Terraform resources or deploy automatically.

## Network prerequisites

- A reachable public UDP endpoint on port 51820. IAP TCP forwarding is **not** a WireGuard UDP endpoint.
- Explicit GCP VPC ingress firewall rule, scoped to intended client public source CIDRs. Do not use 0.0.0.0/0 by default.
- An outbound internet path from the CoreOS VM (external IPv4 or suitable NAT); confirm the actual egress IP.
- Choose a tunnel subnet that does not overlap local, VPC, or destination networks.
- Confirm Fedora CoreOS systemd-networkd owns the host interface and supports WireGuard netdev, IPv4 forwarding and IPMasquerade. Do not replace an active NetworkManager-managed uplink without qualification.

## Keys

Generate one server key and one unique key per client **off-repository** using `wg genkey` and `wg pubkey`. Do not place private keys in Git, Nix store derivations, Terraform variables/state, Ignition user-data, or GCE instance metadata. Copy the server private key to the host using an authenticated secret delivery mechanism. Provisioning private keys is deliberately separate from this repository.

## Host deployment

The supplied networkd files are templates. Render the peer blocks and place:
- `/etc/systemd/network/50-wg-minecraft.netdev` (mode 0600; includes server public peer keys and a reference to private key file)
- `/etc/systemd/network/50-wg-minecraft.network` (mode 0644)
- `/etc/wireguard/minecraft-server.key` (mode 0600, owned by root)

Set the real server private-key path in the netdev template. Each peer has one `[WireGuardPeer]` section with `PublicKey=` and `AllowedIPs=10.77.0.N/32`. Never use broad peer AllowedIPs on the server.

After validating the interface manager and configuration, restart or reload systemd-networkd in a maintenance window, and enable its existing boot service. Changes to host networking can disrupt SSH/IAP. Test on a disposable CoreOS VM before production.

## Client profile

See `client.conf.example`. Replace keys, public endpoint and DNS settings; import into official WireGuard clients on Windows, macOS or Linux. `AllowedIPs=0.0.0.0/0` routes all IPv4 traffic through the gateway, not only Minecraft. This is the simplest cross-platform leak-resistant choice for Minecraft TCP; it also increases VM egress. IPv6 is **not** tunneled by this example. To prevent bypass on dual-stack Minecraft destinations, disable IPv6 for the client session or implement and test an IPv6 tunnel and egress policy. Do not treat the example as an IPv6 kill switch.

## Qualification

1. Confirm VPC firewall permits UDP 51820 only from intended client source ranges, and that the server has a public UDP endpoint.
2. Validate `systemd-analyze verify` for networkd unit compatibility, then inspect `networkctl status wg-minecraft` and `journalctl -u systemd-networkd`.
3. Import a unique client profile, activate the tunnel, and verify handshake counters (using `wg show` where installed).
4. Check a public IPv4 egress service from the client and compare with the VM's observed public egress address. Confirm Minecraft's TCP connection uses the tunnel.
5. Test DNS resolution and IPv6 behavior explicitly; a public-IP check alone does not prove absence of DNS/IPv6 leaks.
6. Reboot a disposable VM and verify networkd recreates the interface and forwarding/NAT without manual intervention.
7. Test client disconnect, unauthorized key rejection, peer isolation, and routing rollback.

No successful runtime qualification is claimed by these templates.
