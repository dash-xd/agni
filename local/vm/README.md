# Fedora CoreOS VM profile (Agni-owned)

This directory supplies application-side host actions for an existing VM
profile. The guest OS, qcow2 artifact, Butane/Ignition generation, first-boot
configuration, guest identity, service contracts and qualification policy are
not Nix-Alpine lifecycle concepts.

The QEMU hypervisor is an implementation primitive and may also boot a
different guest image, such as Grml. There is **no** first-class
`coreos-*` target in the default nix.xd Makefile. A second guest project
supplies its own image, kernel/firmware/boot parameters and qualification
actions without adding Make targets to nix.xd.

The selected Agni source exposes `local/vm/host-actions` via the existing
generic nix.xd `project-host-run`. The host action checks the selected
Git commit against the exact revision staged in the Nix-Alpine writer before
it uses the Agni QEMU flake. Existing QEMU runner image and VM state names
are deliberately unchanged while the old VM1 is active.

Example, from the dated nix.xd controller checkout:

```sh
make project-host-run PROJECT=agni20261112 APPLICATION=vm ACTION=preflight
```

This is read-only preflight of the selected existing guest profile;
`ACTION=build`, `ignition`, `boot`, `stop`, and `reset-failed`
are explicit separate actions and are **not** implied by preflight.
The caller may set `COREOS_PROFILE`, `COREOS_STATE_ROOT`, the
selected image/firmware/SSH fields, and the QEMU backend choice.
These belong to Agni, not to infrastructure Make variables.

`AGNI_VM_VMM=podman` selects the legacy Podman Machine QEMU runner;
`AGNI_VM_VMM=hvf` selects the local Apple HVF adapter for supported
actions. These adapters are a transition path for the qualified VM1,
not a general new VM image contract.

Generic guest Nix application execution uses `make guest-app` with
`GUEST_VM_INSTANCE`, `GUEST_SSH_USER`, `GUEST_SSH_PORT`,
`GUEST_SSH_KEY`, optional `GUEST_KNOWN_HOSTS` and `GUEST_STATE_ROOT`.
No guest OS is assumed by that interface; only a reachable SSH + Bash
guest is required for this particular adapter.

A fully generic QEMU service should eventually accept a content-addressed
disk/kernel artifact, firmware, architecture, CPU/RAM, device/share/network
definitions and persistent instance state; it should not parse Butane,
manage Ignition, test systemd or decide readiness policies. Guest projects
own those semantics.

The historical nix.xd CoreOS and Starwisp controls are retained only under
`ENABLE_LEGACY_VM_PROFILES=1` for existing state/recovery compatibility.
Neither this new host-action wrapper nor its CI static tests proves live
QEMU boot or guest activation on the Mac.
