# Agni production Fedora CoreOS image

This directory builds the operating-system layer used by Agni production Podman hosts.

The build is intentionally split into two concerns:

- **OS composition**: Fedora CoreOS config + rpm-ostree through CoreOS Assembler (COSA).
- **Machine configuration**: Butane/Ignition, metadata, credentials, Quadlets, and workload-specific settings supplied at deployment time.

Do not bake per-instance secrets, hostnames, container deployments, Redis DB assignments, or Cloudflare material into this image.

## Reproducibility

`config.env` pins the Fedora CoreOS configuration commit. Updating the base image is an explicit source change: update `FCOS_CONFIG_REF`, rebuild, validate, and publish a new immutable GCE image.

The preparation step clones the pinned upstream config, removes selected interactive/debugging/hardware-oriented manifest entries, then adds those packages to rpm-ostree `exclude-packages`. This is deliberate: if a retained package hard-depends on an excluded package, rpm-ostree fails the compose instead of silently reintroducing it.

The initial removal set is conservative. It removes user-experience and crash/debug tooling that is not needed to boot GCP, configure networking, run systemd, enforce SELinux, run Ignition/Afterburn, or run Podman. Extend the list only after the resulting image passes the verification and GCP boot tests.

## Required host capabilities

- Podman
- `/dev/kvm`
- `/dev/fuse`
- enough disk space for a COSA build
- network access to Fedora/CoreOS repositories

COSA image construction requires KVM. The wrapper follows the upstream rootless Podman invocation pattern and mounts the work directory at `/srv`.

## Build

```sh
make production
```

or directly:

```sh
./production/build.sh all
```

Targets:

```sh
./production/build.sh compose
./production/build.sh qemu
./production/build.sh iso
./production/build.sh gcp
./production/build.sh all
```

Outputs are copied to `production/dist/` and include the live ISO and the GCP `*.tar.gz` artifact emitted by `cosa osbuild gcp`. The GCP artifact already contains `disk.raw`, uses old GNU tar format, is gzip-compressed, and receives the GCP platform customization from osbuild.

## Updates

Agni treats the OS image itself as a versioned deployment artifact. Zincati is masked and rpm-ostree automatic updates/layering are disabled in the image. Updating the OS means publishing a new GCE image and rolling instances/templates forward, not allowing a host to rejoin the upstream Fedora CoreOS update graph on its own.

`rpm-ostree` and OSTree remain present because they are part of the CoreOS platform and useful for introspection/recovery. Application software belongs in Podman images, not rpm-ostree layers.

## Verification

`verify.sh` performs static artifact checks. A complete release gate should additionally boot the QEMU image and the published GCP image and verify:

- Ignition completes successfully
- GCP metadata/Afterburn integration works
- SELinux is enforcing
- `systemctl --failed` is empty
- DNS and outbound HTTPS work
- Podman bridge networking works
- Podman host networking works where used
- rootless Podman works if the deployment requires it
- Quadlets start and survive reboot
- SSH/IAP recovery access works when enabled
- Zincati remains disabled
- rpm-ostree automatic updates/layering remain disabled

## GCP publication

The Terraform module at `../../../terraform/coreos-image` imports the generated GCP archive from GCS as an immutable `google_compute_image` and publishes it under an image family. The example workflow at `../../../docs/external-coreos-image-workflow.yml.example` is intentionally **not** in `.github/workflows`: it is reference material to be copied/adapted into the separate deployment repository that owns GCP WIF, Terraform state, image publication, instance templates, and rollouts.
