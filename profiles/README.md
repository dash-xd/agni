# Agni installation profiles

Agni profiles/components are built from shared infrastructure primitives. A caller selects one profile tool; that profile owns its source, configuration, lifecycle policy, and internal use of the shared Terraform library.

The operator never enumerates a profile's internal Terraform modules separately.

## Probe

Probe is the small reusable Agni component:

```text
IPv4            /29, 4 GCP-usable addresses
lifecycle       transient systemd smoke-testing idiom
frontends       Nginx execution + Squid egress
Fatline         no full durable Fatline requirement
Logma           not required
serverless      optional Gen1/Gen2 shadow functions
```

`cmd/probe` seeds the complete source tree:

```bash
probe seed <root>
```

The Smoke environment name is independent. The intended current use is:

```bash
smoke env create astrochicken
smoke env tool add astrochicken github.com/dash-xd/agni/cmd/probe@<sha>
smoke env tool run astrochicken probe seed <root>
```

So `Probe` is the reusable Agni composition; `astrochicken` is one local Smoke environment built from it.

## Gateway

Gateway is the durable installation profile that composes from Probe's reusable capabilities plus Gateway-specific durable policy:

```text
IPv4            /28, 12 GCP-usable addresses
lifecycle       persistent Fedora CoreOS + Quadlet at boot
frontends       Nginx + Squid
Fatline         full durable Fatline
Logma           required
Redis/runtime   persistent gateway runtime components
```

Gateway may reuse Probe frontend/runtime building blocks and the same shared Terraform primitives, but it owns its own `/28` HCL and persistent lifecycle. Do not implement Gateway by seeding Probe's `/29` root and mutating it afterward.

The existing top-level `terraform/` installation is the migration source for the `/28` network and persistent FCOS/Quadlet pieces. It is not yet a complete Gateway profile because the full Logma/Fatline graph is not represented there yet.

Do not expose `cmd/gateway seed` until the profile is complete. Once complete its surface is:

```bash
smoke env create gateway
smoke env tool add gateway github.com/dash-xd/agni/cmd/gateway@<sha>
smoke env tool run gateway gateway seed <root>
```

## Dependency authority

Profile HCL is authoritative for module imports. Profile Go code does not repeat the module list. Seeding supplies Agni's shared module library under `modules/`; Terraform resolves the imports declared by HCL.

There is no `tf seed --module ...` operator step.

## Composition rule

```text
Agni Probe          reusable transient base/component
Agni Gateway        durable composition extending Probe capabilities
Smoke env name      local role/lifecycle label
shared module       implementation primitive
Terraform           authoritative dependency/lifecycle engine
Huram               exact candidate/values/credentials/evidence
```
