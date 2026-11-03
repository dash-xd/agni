# Minimal FCOS qualification profile

This profile composes a Fedora CoreOS OCI base into a smaller OS image. It
removes the listed optional host packages, but deliberately retains Podman,
crun, systemd, Ignition, Afterburn, SELinux, NetworkManager and rpm-ostree.
No Docker daemon or Kubernetes distribution is required.

The image build is controlled by
`xd-dash/huram-abi-master/.github/workflows/slim-fcos-qemu.yml`.
The workflow resolves the base image into a digest, records its identity,
uses the upstream OSBuild image generator, and creates QEMU and live ISO
artifacts. The separate ISO and disk boot tests must pass before artifacts
are marked qualified. The Build does not deploy anything to GCE.

`render-ignition.py` produces a Butane file with an administrative `core`
account and optional unprivileged login account. The actual root account
remains distinct and locked. Credentials are supplied at qualification time
and are not baked into the OS OCI image. In CI ephemeral SSH keys are
generated; do not deploy images or provisioned disks with test keys.

The bootable ISO and QEMU disk image are distinct outputs from the same
OS composition. The ISO requires `coreos-installer iso customize
--live-ignition` to make the live boot testable with those ephemeral keys.
A future GCP image must be built and verified separately; GCE does not
boot the ISO artifact.

`qualify-qemu.sh` runs QEMU inside the Nix-Alpine toolbox container,
checks the OS package contract, proves passwordless `core` sudo and
optional nonprivileged SSH login, checks rootless Podman, and executes a
transient systemd service. KVM absence fails closed on Blacksmith; for
local-only experiments `ALLOW_TCG=true` permits slow software emulation.

Do not infer filesystem savings from the RPM count: compare compressed
ISO/QCOW2 sizes, actual `df` data, and cold-boot time against stock FCOS.
