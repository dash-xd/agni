# Agni installation profiles

Agni profiles/components are built from shared infrastructure primitives. A caller selects one profile tool; that profile owns its source, configuration, lifecycle policy, and internal use of the shared Terraform library.

The operator never enumerates a profile's internal Terraform modules separately.

## Probe

Probe is the small reusable Agni component:

```text
IPv4            /29, 4 GCP-usable addresses
lifecycle       transient systemd smoke-testing intent
frontend assets Nginx execution + Squid egress configuration
Fatline         no full durable Fatline requirement
Logma           not required
serverless      optional Gen1/Gen2 shadow functions
```

`cmd/probe` seeds the complete profile source tree:

```bash
probe seed <root>
```

The Smoke environment name is independent. The current Smoke use is:

```bash
smoke env create astrochicken
smoke env tool add astrochicken github.com/dash-xd/agni/cmd/probe@<exact-sha>
smoke env shell astrochicken <session-root>

go tool probe seed ./agni-probe
terraform -chdir=./agni-probe init
terraform -chdir=./agni-probe plan -var-file=../config/probe.tfvars
```

There is no `smoke env tool run` or `smoke env terraform` command. Environment-scoped Go tools are invoked through ordinary `go tool` inside the immutable Smoke child environment; Terraform remains a native executable.

So `Probe` is the reusable Agni composition; `astrochicken` is one local Smoke environment built from it.

### Current frontend/lifecycle wiring status

Probe seeds these profile-owned text assets:

```text
config/nginx.conf
config/squid.conf
config/lifecycle.env
```

They define the intended transient frontend/lifecycle configuration, but the current Probe Terraform root does **not yet** project those files into `coreos-node.user_data` or otherwise install/start them. The current HCL provisions the `/29` regional cell, nodes, internal service addresses, and optional Gen1/Gen2 shadow functions from a caller-supplied source instance template.

Therefore:

- seeding proves the exact profile assets are present;
- Terraform apply proves the infrastructure represented by the current HCL;
- neither fact alone proves Nginx/Squid/transient-systemd runtime readiness;
- a qualification must not claim those frontends are deployed until a profile-owned launcher/Butane/Ignition path consumes the seeded assets and that execution class is tested.

When that wiring is added, keep Butane/Ignition/native systemd semantics authoritative rather than duplicating them in a Go/Terraform DSL.

### Seed ownership

Within a Probe root, root `*.tf`, `config/`, and `modules/` are profile-owned source. Reseeding reconciles those paths so removed profile source cannot survive and continue affecting Terraform/bootstrap behavior. Terraform runtime/state artifacts such as `.terraform/` and `terraform.tfstate` are not profile source and are preserved.

Deployment-specific values should live outside the profile source tree, for example in a sibling `config/probe.tfvars` selected by the Smoke/Huram session.

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

Do not expose `cmd/gateway seed` until the profile is complete. Once complete its intended use follows the same native pattern:

```bash
smoke env create gateway
smoke env tool add gateway github.com/dash-xd/agni/cmd/gateway@<exact-sha>
smoke env shell gateway <session-root>

go tool gateway seed ./agni-gateway
terraform -chdir=./agni-gateway init
terraform -chdir=./agni-gateway plan -var-file=../config/gateway.tfvars
```

## Dependency authority

Profile HCL is authoritative for module imports. Profile Go code does not repeat the module list. Seeding supplies Agni's shared module library under `modules/`; Terraform resolves the imports declared by HCL.

There is no `tf seed --module ...` operator step.

## Composition rule

```text
Agni Probe          reusable transient component/profile source
Agni Gateway        future durable composition extending shared capabilities
Smoke env name      local execution/composition label
shared module       implementation primitive
Terraform           authoritative infrastructure lifecycle/state engine
Huram               exact candidate/values/credentials/evidence
```
