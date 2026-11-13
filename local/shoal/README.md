# Shoal: one Farcaster, one World 1

Agni owns the logical plan in `plan.json`. The physical Farcaster remains
the already-qualified Starwisp VM. This stage adds **one** independently
bootable World 1 with its own QCOW2 overlay, Ignition, boot ID, hostname
and SSH host identity. Both use the same host-owned Nix store through
read-only VirtIO 9P; they do **not** share a writable guest disk.

The generic `nix.xd` Makefile only stages committed sources and invokes
Agni host actions. World 1 runs in the existing `coreos-arm64` Podman
Machine, without restarting or rewriting Starwisp.

## Prepare

From `~/workspace/nix.xd20261113.0`, fast-forward the Agni checkout
and stage its new exact revision:

```sh
git -C ../agni20261113.0 pull --ff-only
AGNI_REV="$(git -C ../agni20261113.0 rev-parse HEAD)"
make stage PROVIDER=podman MACHINE=coreos-arm64 CHECKOUT=agni20261113.0
```

The existing Starwisp artifact state must contain the qualified
`build.txt` and `base.qcow2` at
`~/.local/state/nix-xd/coreos/starwisp/`. No image rebuild or disk copy
is needed: World 1 uses its **own** QCOW2 overlay referencing that base.

## First-boot lifecycle

```sh
make project-host-run PROVIDER=podman MACHINE=coreos-arm64 \
  PROJECT=agni20261113.0 PROJECT_REV="$AGNI_REV" \
  APPLICATION=shoal ACTION=world1-ignition

make project-host-run PROVIDER=podman MACHINE=coreos-arm64 \
  PROJECT=agni20261113.0 PROJECT_REV="$AGNI_REV" \
  APPLICATION=shoal ACTION=world1-preflight

make project-host-run PROVIDER=podman MACHINE=coreos-arm64 \
  PROJECT=agni20261113.0 PROJECT_REV="$AGNI_REV" \
  APPLICATION=shoal ACTION=world1-start
```

`world1-ignition` selects the dedicated
`#ignitionShoalWorld1_9p` Nix output. The user `wisp` is authorized
with `~/.ssh/starwisp-test.pub` by default, or the explicit
`SHOAL_SSH_PUBLIC_KEY=/absolute/path/to/key.pub` override.
This is only an SSH *client authorization* key. The guest generates its
own SSH **server host key** on first boot.

`world1-start` is a managed, idempotent start: a subsequent run
checks the recorded identity and existing overlay instead of creating
a new VM. It does not restart Farcaster. It does not activate Logmash.

## SSH host-key trust and binding

Once the VM's SSH server is reachable:

```sh
make project-host-run PROVIDER=podman MACHINE=coreos-arm64 \
  PROJECT=agni20261113.0 PROJECT_REV="$AGNI_REV" \
  APPLICATION=shoal ACTION=hostkey-plan
```

This shows the World 1 ED25519 host-key SHA256 fingerprint, but does **not**
automatically trust it. Compare it against independent guest-console
or other trusted out-of-band evidence where available. SSH keyscan by
itself is **TOFU**, not cryptographic VM attestation.

Then explicitly approve the displayed fingerprint (replace the
placeholder, which is not a real fingerprint):

```sh
make project-host-run PROVIDER=podman MACHINE=coreos-arm64 \
  PROJECT=agni20261113.0 PROJECT_REV="$AGNI_REV" \
  APPLICATION=shoal ACTION=hostkey-enroll \
  SHOAL_WORLD1_HOSTKEY_CONFIRM=SHA256:REPLACE_WITH_VERIFIED_FINGERPRINT
```

Enrollment requires a matching managed World container ID, disallows
reuse of Farcaster's host key, and writes
`~/.local/state/nix-xd/coreos/shoal-world1/known_hosts`
without overwriting a conflicting entry.

With that pin established, the existing Agni actions check **both**
physical guests and their independent boot IDs:

```sh
make project-host-run PROVIDER=podman MACHINE=coreos-arm64 \
  PROJECT=agni20261113.0 PROJECT_REV="$AGNI_REV" \
  APPLICATION=shoal ACTION=bind SHOAL_STAGE=world1

make project-host-run PROVIDER=podman MACHINE=coreos-arm64 \
  PROJECT=agni20261113.0 PROJECT_REV="$AGNI_REV" \
  APPLICATION=shoal ACTION=storage SHOAL_STAGE=world1
```

A passing World storage gate proves two bound guests, read-only 9P
and two disposable rootless readers **per guest**. It does not prove
network connectivity, guest-local writable store independence, service
placement, Probot or Logmash. Those require subsequent qualifications.

## Local regression tests

```sh
python3 ../agni20261113.0/local/shoal/test_binding.py
python3 ../agni20261113.0/local/shoal/test_storage.py
python3 ../agni20261113.0/local/shoal/test_world1.py
```

For a damaged or failed *World 1 only*, use Agni's explicit VM
`reset-failed` action with `COREOS_PROFILE=shoal-world1` and
`COREOS_CONTAINER_NAME=coreos-shoal-world1`; do not reset Starwisp.
The guest overlay and artifacts must be reconciled before recreation.


## Inter-VM network candidate (preflight only)

The declared `networkCandidate` is a **proposal**, not a deployed
network. The running VMs each use a separate QEMU user-mode NAT backend.
Neither existing 127.0.0.1 SSH forwarding port provides VM-to-VM routing.

The proposed transport is a QEMU socket pair over a dedicated internal
Podman network with static guest transit addresses. Guest default
routes must not use the transit NIC, and the existing QEMU user backend
must be hardened with `restrict=on` while preserving its explicit
host-to-guest SSH forwarding. IPv4 and IPv6 guest egress, management
reachability, inter-VM service ACLs, and Squid policy require separate
runtime tests. No connectivity or egress guarantee is made by the plan.

First, run the **read-only** Agni network prerequisite check after staging
the updated source:

```sh
make project-host-run PROVIDER=podman MACHINE=coreos-arm64 \
  PROJECT=agni20261113.0 PROJECT_REV="$AGNI_REV" \
  APPLICATION=shoal ACTION=network-preflight
```

This validates the exact Agni revision, current two-VM physical binding,
original QEMU user-mode network arguments, rootless management tools and
guest network tools, and records (but does not require) noninteractive sudo.
Guest network mutation must be provisioned declaratively in CoreOS rather\nthan granting the login account unrestricted administrative access.
Its receipt explicitly leaves
`network`, `egress` and `services` as **not assessed**.

A future explicit migration must safely stop/recreate QEMU containers
against the **existing** guest overlays, and requalify new boot IDs and
storage. Do not delete existing identity/storage receipts: they describe
the previously qualified physical configuration. Do not reuse them as
evidence for the new QEMU network topology.


## Network migration preparation (unapplied)

After network preflight passes, run:

```sh
make project-host-run PROVIDER=podman MACHINE=coreos-arm64 \
  PROJECT=agni20261113.0 PROJECT_REV="$AGNI_REV" \
  APPLICATION=shoal ACTION=network-migration-prepare
```

The read-only action validates exact running container/manifest IDs,
boot identities, original QEMU user-mode networks and existing QCOW2 overlay
paths. It inspects guest IPv4 addresses/routes through pinned SSH and creates
candidate MAC-matched NetworkManager keyfiles and QEMU socket arguments
under `~/.local/state/agni/shoal/network-migration/`.

It does **not** install the keyfiles, copy live QCOW2 disks, restart a VM,
or activate networking. Every result explicitly reports
`AGNI_SHOAL_MIGRATION_ACTIVATE=blocked` and leaves all network/egress
gates as not assessed.

The outstanding cutover requirements are a narrowly scoped, qualified
root-owned network configuration installer for already-initialized CoreOS,
consistent stopped-guest backups of both existing overlays, management SSH
survivability testing, and fail-closed IPv4/IPv6/ Squid policy qualification.
Historical binding and storage receipts are retained but cannot attest
the post-restart physical topology.
