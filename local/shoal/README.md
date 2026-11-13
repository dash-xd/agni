# One-Farcaster / one-World binding preflight

Agni owns the logical placement plan in `plan.json`. The physical entries
preserve the existing Starwisp-based Farcaster candidate and reserve World 1.
No VM is created and no application service is activated by the binding action.

Run from the sibling nix.xd checkout (the project checkout must be named
`agni20261112` in the same workspace):

```sh
AGNI_REV="$(git -C ~/workspace/agni20261112 rev-parse HEAD)"
make project-host-run \
  PROJECT=agni20261112 APPLICATION=shoal ACTION=bind \
  PROJECT_REV="$AGNI_REV" SHOAL_STAGE=farcaster
```

The action is read-only except for a receipt written to
`~/.local/state/agni/shoal/receipts`. It checks the selected commit,
the exact QEMU runner ID, the expected loopback SSH publication, strict
pinned SSH host identity, and the guest boot ID. It uses
`~/.local/state/nix-xd/coreos/<instance>/known_hosts` by default.
Override `SHOAL_MACHINE`, `SHOAL_STATE_ROOT`, or `SHOAL_SSH_KEY`
only when selecting a different existing runtime.

To run the storage gate, stage the selected committed nix.xd checkout in
Nix-Alpine, then invoke the Agni-owned storage action:

```sh
make stage CHECKOUT="$(basename "$PWD")"
make project-host-run \
  PROJECT=agni20261112 APPLICATION=shoal ACTION=storage \
  PROJECT_REV="$AGNI_REV" SHOAL_STAGE=farcaster PROVIDER=podman
```

This requires the selected Podman writer `nix-xd-arm`, its mounted
`nix-xd-arm-store` volume, and the pre-existing QEMU runner. It executes
the two rootless, read-only 9P readers per guest and reattests the physical
binding afterwards. Both the binding and the storage receipt are
content-addressed and written outside either Git checkout.

Once World 1 is running, use `SHOAL_STAGE=world1` for **both** actions.
That stage requires distinct Farcaster/World container IDs and boot IDs,
and a successful storage probe in each VM.


Binding evidence is **not** evidence that 9P, guest-local stores, the shared
network, IPv4/IPv6 egress denial, Squid, or Fatline services work. Each must
receive a separately verified gate; do not promote a successful binding to
a Shoal or Fatline pass. This branch does not implement the shared network or application gates.

Run the host-independent regression gate with:

```sh
python3 ~/workspace/agni20261112/local/shoal/test_binding.py
python3 ~/workspace/agni20261112/local/shoal/test_storage.py
```
