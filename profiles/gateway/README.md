# Gateway installation profile

Gateway is the durable Agni installation profile. It is distinct from the Astrochicken probe even when both reuse lower-level networking and frontend primitives.

## Required contract

```text
IPv4          /28, 16 total addresses, 12 GCP-usable addresses
lifecycle     Fedora CoreOS + persistent Quadlet at boot
frontends     Nginx execution + Squid egress
Logma         required
Fatline       full durable service/resource graph
runtime       persistent Redis and gateway services
```

## Migration source

The current top-level `terraform/` installation already contains useful Gateway pieces:

- `/28` regional subnet and 12-slot addressing semantics;
- Fedora CoreOS provisioning;
- bootstrap configuration;
- Nginx and Squid Quadlet assets;
- durable boot-time service configuration.

Those pieces should be migrated/recomposed here over the shared modules in `terraform/modules` rather than copied into a second independent infrastructure implementation.

## Completion gate

Do **not** add `cmd/gateway` until this profile contains the complete durable graph promised by the name, including Logma/Fatline and the persistent gateway runtime.

Once complete, its operator surface is exactly one profile seed:

```bash
smoke env create gateway
smoke env tool add gateway github.com/dash-xd/agni/cmd/gateway@<agni-sha>
smoke env tool run gateway gateway seed <root>
smoke env terraform gateway --dir <root> -- plan
```

There must not be a subsequent `tf seed`, module list, or shell-side dependency declaration. Gateway HCL/configuration owns its composition; the profile seeder only makes its shared implementation library and profile assets available.

## Relationship to Astrochicken

```text
Astrochicken                     Gateway
------------                     -------
/29                              /28
4 usable IPv4                    12 usable IPv4
transient systemd lifecycle      persistent Quadlet lifecycle
Nginx + Squid                    Nginx + Squid
no required Logma                Logma required
no full Fatline                  full Fatline
probe                            durable installation
```

Share primitives and config fragments where they are genuinely identical. Do not express Gateway as an Astrochicken mode flag when the lifecycle and durable graph differ.
