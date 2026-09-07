# Gateway installation profile

Gateway is the durable Agni installation profile. It is composed from reusable Probe capabilities and shared Agni primitives, then adds Gateway-specific network, lifecycle, and durable service policy.

## Required contract

```text
IPv4          /28, 16 total addresses, 12 GCP-usable addresses
lifecycle     Fedora CoreOS + persistent Quadlet at boot
frontends     Nginx execution + Squid egress
Logma         required
Fatline       full durable service/resource graph
runtime       persistent Redis and gateway services
```

## Composition from Probe

Probe is not a parent root that Gateway patches. Probe's `/29` HCL and transient systemd lifecycle remain Probe-specific policy.

Gateway should reuse Probe-owned capabilities only where their contracts remain valid, while supplying its own durable profile root:

```text
shared Agni primitives
        |
        v
Probe reusable capabilities
        |
        +-- Probe profile
        |     /29 + transient lifecycle
        |
        `-- Gateway profile
              /28 + persistent lifecycle
              + Logma
              + Fatline
```

This avoids both duplication and configuration override chains.

## Migration source

The current top-level `terraform/` installation already contains useful Gateway pieces:

- `/28` regional subnet and 12-slot addressing semantics;
- Fedora CoreOS provisioning;
- bootstrap configuration;
- Nginx and Squid Quadlet assets;
- durable boot-time service configuration.

Those pieces should be migrated/recomposed here over Probe/shared Agni building blocks rather than copied into a second independent implementation.

## Completion gate

Do **not** add `cmd/gateway` until this profile contains the complete durable graph promised by the name, including Logma/Fatline and the persistent gateway runtime.

Once complete, its operator surface is exactly one profile seed:

```bash
smoke env create gateway
smoke env tool add gateway github.com/dash-xd/agni/cmd/gateway@<agni-sha>
smoke env tool run gateway gateway seed <root>
smoke env terraform gateway --dir <root> -- plan
```

There must not be a subsequent `tf seed`, module list, or shell-side dependency declaration.
