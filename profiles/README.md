# Agni installation profiles

Agni profiles are complete installation recipes built from shared infrastructure primitives. A caller selects a profile; the profile owns its configuration files and its shared-module dependency graph.

The operator must never enumerate a profile's internal Terraform modules separately.

```text
Smoke environment
    |
    `-- exact Agni profile tool
            |
            +-- profile configuration
            +-- profile workload/bootstrap policy
            `-- shared Agni Terraform modules
                    |
                    `-- native Terraform
```

## Astrochicken

Astrochicken is the small probe profile.

```text
IPv4            /29, 4 GCP-usable addresses
lifecycle       transient systemd smoke-testing idiom
frontends       Nginx execution + Squid egress
Fatline         no full Fatline requirement
Logma           not required
serverless      optional Gen1/Gen2 shadow functions
```

The profile currently lives in `profiles/astrochicken`. `cmd/astrochicken` seeds a complete root, including the exact shared modules its `.tf` files import.

```bash
astrochicken seed <root>
```

There is no second `tf seed --module ...` step.

## Gateway

Gateway is the durable installation profile that the current larger Agni installation is converging toward.

```text
IPv4            /28, 12 GCP-usable addresses
lifecycle       persistent Fedora CoreOS + Quadlet at boot
frontends       Nginx + Squid
Fatline         full Fatline
Logma           required as part of the durable graph
Redis/runtime   persistent gateway runtime components
```

The existing top-level `terraform/` installation contains the `/28` network and persistent FCOS/Quadlet bootstrap pieces and is the migration source for this profile. Do not call that installation `tf`: `terraform` is the implementation language/tool boundary, not the installation identity.

Before exposing `cmd/gateway seed`, finish moving the complete durable Fatline/Logma runtime into the Gateway profile so the command cannot imply a partially assembled gateway.

## Shared modules

Reusable implementation stays under `terraform/modules` and remains free of profile policy where possible. Examples include `regional-network`, `regional-cell`, `coreos-node`, and the Gen1/Gen2 function modules.

Profiles may import those modules in their `.tf` files and select them internally in Go when seeding. The dependency graph belongs to the profile source and exact Agni SHA, not to the shell command line.

## Composition rule

```text
profile name       = installation design
Smoke env name     = local role/lifecycle label
shared module      = implementation primitive
Terraform          = authoritative infrastructure engine
Huram              = exact candidate/values/credentials/evidence
```

An environment named `probe`, `gateway-test`, or `us-west1` may run the Astrochicken profile. Environment names do not select profiles implicitly.
