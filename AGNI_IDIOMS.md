# Agni Go-first cloud/profile idiom

Agni is the reusable cloud/virtualization implementation and installation-profile layer. It owns generic infrastructure primitives plus reusable installation components/profiles in the infrastructure domains it actually owns. It does not own organization credentials, Huram qualification policy, Smoke environment semantics, or unrelated provider-specific control-plane profiles merely because they also use Terraform.

## Authority

```text
Huram
  exact candidates + values + credentials + evidence + promotion
      |
      v
Smoke
  generic named environments + immutable Go tool execution
      |
      v
Agni profile/component tool
  installation source/configuration
      |
      +-- profile HCL/config
      +-- lifecycle/workload policy
      `-- shared Agni Terraform library
              |
              v
      Terraform / Butane / native tools
```

Smoke environment names are operator-local labels. They never select an Agni component implicitly.

Smoke is a composition/execution convenience, not an Agni dependency. Agni packages and installable tools must remain directly usable with ordinary Go/native tooling when Smoke is not involved.

## Native source remains authoritative

Terraform owns HCL, providers, variables, module imports, backends, state, plan/apply/destroy/output semantics. Butane owns Butane/Ignition transformation. QEMU and gcloud own their native argument/command contracts.

Do not mirror those languages into a Go DSL or a second dependency manifest.

## Profiles own composition

A profile seed produces one complete source tree:

```text
<root>/
  main.tf
  variables.tf
  outputs.tf
  profile config/workload files
  modules/
    shared Agni Terraform library
```

The profile HCL is the only authority for which shared modules are imported. Go code MUST NOT carry a second list of the same module dependencies, and operators MUST NOT enumerate them on the command line.

Agni's `terraform.Seed(root)` therefore makes the shared module library available under `modules/` as an implementation detail. Terraform resolves the actual `source = "./modules/..."` imports declared by the profile.

There is no public `cmd/tf` composition step.

## Identity ownership

Agni-owned source, resource metadata, labels, config keys, and runtime conventions must use Agni/profile vocabulary rather than Smoke environment vocabulary.

For example, Probe may emit `probe-role` or another Probe-owned key. It must not emit `smoke-role`, because a caller can use Probe without Smoke and a Smoke environment can be named anything.

Likewise `astrochicken` is not an Agni profile name. It is the current Smoke environment name used when deploying Probe.

## Seed is vocabulary, not shared implementation

`seed` means exact-source destination preparation, but implementations remain domain-specific:

```text
ghxd/worktree seed
  Git repository/SHA/auth/object/ref/worktree operations

Agni profile seed
  embedded profile/config/shared-source filesystem preparation
```

Agni MUST NOT reuse ghxd/worktree implementation merely because both use the verb `seed`. Do not reintroduce `materialize` as a parallel public verb for this boundary.

## Provider ownership boundary

Terraform is an implementation language, not an ownership namespace. A Terraform module/profile belongs with the domain that owns the resources and reconciliation contract.

In particular, Cloudflare DNS/xdroute projection belongs to cfxd, not Agni:

```text
Agni profile: probe
  CoreOS/network/runtime substrate

cfxd profile: dns-txt
  Cloudflare TXT reconciliation for xdroute metadata
```

A Smoke environment such as `astrochicken` may compose both profiles independently. `cfxd/dns-txt` is optional observability/discovery infrastructure and is not a dependency of Agni Probe.

Do not place cfxd profiles or Cloudflare DNS reconciliation under `terraform/modules` merely because Agni already has Terraform seeding machinery. Independently owned profiles should keep independent Terraform roots/state lifecycles unless a concrete cross-domain requirement proves that coupling necessary.

The older top-level `terraform/cloudflare-zone` root predates this boundary and is migration debt. Do not grow new Cloudflare policy there; move provider-specific behavior to cfxd when that root is next migrated.

## Shared Terraform primitives

Reusable implementation stays under `terraform/modules` and remains free of installation-profile vocabulary where practical:

```text
regional-network
regional-internal-addresses
coreos-node
regional-cell
cloud-function-v1-http
cloud-function-v2-http
```

These are a library, not an operator-facing installation selector.

## Probe

Probe is the small reusable installation component under `profiles/probe`:

```text
IPv4          /29, 4 GCP-usable addresses
lifecycle     transient systemd smoke-testing lifecycle
frontends     Nginx execution + Squid egress
Logma         not required
Fatline       no full durable Fatline requirement
serverless    optional Gen1/Gen2 shadow functions
```

The installable tool is:

```text
github.com/dash-xd/agni/cmd/probe
```

and its complete preparation surface is:

```bash
probe seed <root>
```

That one command seeds the Probe source/configuration and shared Terraform library. The operator does not run a second module-seeding command.

`Probe` is an Agni composition identity. A Smoke environment may be named `astrochicken`, `test`, `us-west1`, or anything else while using Probe.

## Gateway

Gateway is the durable installation profile that grows from Probe's reusable capabilities while owning different network and lifecycle policy:

```text
IPv4          /28, 12 GCP-usable addresses
lifecycle     persistent Fedora CoreOS + Quadlet at boot
frontends     Nginx + Squid
Logma         required
Fatline       full durable Fatline graph
runtime       persistent Redis/gateway services
```

Gateway composition should reuse Probe-owned implementation only where the semantics are genuinely shared, such as common frontend/runtime building blocks. Gateway MUST NOT seed Probe's `/29` root and then patch/override it. `/29` remains Probe policy; `/28` remains Gateway policy.

The intended shape is:

```text
shared Agni primitives
        |
        v
Probe reusable capabilities
        |
        +-- transient Probe profile (/29)
        |
        `-- Gateway composition
              +-- Gateway /28 policy
              +-- persistent FCOS/Quadlet lifecycle
              +-- Logma
              `-- full Fatline runtime
```

The existing top-level `terraform/` installation is the migration source for the `/28`, FCOS bootstrap, Nginx/Squid Quadlet, and related durable infrastructure pieces. It is not yet the complete Gateway profile because the full Logma/Fatline runtime has not been moved into that profile.

The legacy top-level installation root is migration input, not a second canonical profile. Do not add new Probe/Gateway policy there. Move reusable behavior downward into shared modules/config packages and move durable installation behavior into `profiles/gateway`. Retire the old root once Gateway supersedes it.

Do not expose `cmd/gateway seed` until that graph is complete. Once complete, Gateway follows the same one-profile/one-seed contract as Probe.

## Smoke use

Probe in an Astrochicken environment:

```bash
smoke env create astrochicken
smoke env tool add astrochicken github.com/dash-xd/agni/cmd/probe@<exact-sha>
smoke env shell astrochicken <session-root>

go tool probe seed ./agni-probe
terraform -chdir=./agni-probe init
terraform -chdir=./agni-probe plan
```

A separately composed cfxd profile may seed its own sibling Terraform root in the same Smoke session without becoming part of Probe.

Eventually Gateway uses the same pattern with its own environment and profile tool.

Environment role and Agni composition identity are orthogonal.

## Change protocol

1. Huram owns exact candidates, credentials, deployment values, evidence, and promotion.
2. Smoke owns generic environment/snapshot/tool/native execution.
3. Agni owns reusable infrastructure primitives and installation profiles/components in Agni's infrastructure domain.
4. Keep provider-specific control-plane profiles with their provider owner; Cloudflare DNS/xdroute projection belongs to cfxd.
5. Keep Agni directly usable without requiring Smoke.
6. Profile HCL/config is authoritative for profile composition.
7. Never duplicate a profile's module dependency graph in Go or shell arguments.
8. Seed the shared Terraform library as an internal implementation detail, not as an operator step.
9. Keep Agni/profile resource metadata independent of Smoke environment identity.
10. Keep Probe transient and `/29`; keep Gateway durable and `/28`.
11. Compose Gateway from reusable Probe capabilities and shared primitives, not by patching a seeded Probe root.
12. Freeze the legacy top-level installation root to migration/compatibility work; do not grow new profile policy there.
13. Do not expose an installation-profile command until that profile's promised service graph is complete.
14. Preserve Terraform/Butane/QEMU/gcloud as authoritative native contracts.
15. Use `seed` as common vocabulary without sharing unrelated provider/domain implementations.
