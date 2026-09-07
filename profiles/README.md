# Agni installation profiles

Agni profiles are complete installation recipes built from shared infrastructure primitives. A caller selects one profile tool; that profile owns its source, configuration, lifecycle policy, and internal use of the shared Terraform library.

The operator never enumerates a profile's internal Terraform modules separately.

```text
Smoke environment
    |
    `-- exact Agni profile tool
            |
            +-- profile HCL/config
            +-- workload/lifecycle policy
            `-- shared Agni Terraform library
                    |
                    `-- native Terraform
```

## Dependency authority

Profile HCL is authoritative for module imports:

```hcl
module "region" {
  source = "./modules/regional-cell"
}
```

Profile Go code does not repeat that list. Seeding simply places the shared Agni module library under `modules/`, after which Terraform resolves the imports declared by HCL.

There is no `tf seed --module ...` operator step.

## Astrochicken

Astrochicken is the small probe profile:

```text
IPv4            /29, 4 GCP-usable addresses
lifecycle       transient systemd smoke-testing idiom
frontends       Nginx execution + Squid egress
Fatline         no full durable Fatline requirement
Logma           not required
serverless      optional Gen1/Gen2 shadow functions
```

`cmd/astrochicken` seeds the complete profile source tree:

```bash
astrochicken seed <root>
```

## Gateway

Gateway is the durable installation profile:

```text
IPv4            /28, 12 GCP-usable addresses
lifecycle       persistent Fedora CoreOS + Quadlet at boot
frontends       Nginx + Squid
Fatline         full durable Fatline
Logma           required
Redis/runtime   persistent gateway runtime components
```

The existing top-level `terraform/` installation is the migration source for the `/28` network and persistent FCOS/Quadlet pieces. It is not yet a complete Gateway profile because the full Logma/Fatline graph is not represented there yet.

Do not expose `cmd/gateway seed` until the profile is complete. Once complete it must have the same simple surface:

```bash
gateway seed <root>
```

with no second shared-module command.

## Shared implementation

Reusable implementation remains under `terraform/modules`. Profiles may share networking, node, address, and serverless primitives while retaining distinct installation policy.

```text
Astrochicken                Gateway
   |                           |
   +---- shared modules -------+
   |                           |
 transient lifecycle        durable lifecycle
 /29                       /28
 nginx+squid               nginx+squid+Logma+Fatline
```

Do not make Gateway a flag mode of Astrochicken merely because they share primitives. Their lifecycle and durable service graphs are intentionally different.

## Composition rule

```text
profile name       = installation design
Smoke env name     = local role/lifecycle label
shared module      = implementation primitive
Terraform          = authoritative dependency/lifecycle engine
Huram              = exact candidate/values/credentials/evidence
```

An environment named `probe`, `gateway-test`, or `us-west1` may run the Astrochicken profile. Environment names do not select profiles implicitly.
