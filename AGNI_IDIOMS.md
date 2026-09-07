# Agni Go-first cloud/profile idiom

Agni is the reusable cloud/virtualization implementation and installation-profile layer. It owns generic infrastructure primitives plus complete installation profiles. It does not own organization credentials, Huram qualification policy, or Smoke environment semantics.

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
Agni profile tool
  complete installation source/configuration
      |
      +-- profile HCL/config
      +-- profile lifecycle/workload policy
      `-- shared Agni Terraform library
              |
              v
      Terraform / Butane / native tools
```

Smoke environment names are operator-local labels. They never select a profile implicitly.

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

## Seed is vocabulary, not shared implementation

`seed` means exact-source destination preparation, but implementations remain domain-specific:

```text
ghxd/worktree seed
  Git repository/SHA/auth/object/ref/worktree operations

Agni profile seed
  embedded profile/config/shared-source filesystem preparation
```

Agni MUST NOT reuse ghxd/worktree implementation merely because both use the verb `seed`. Do not reintroduce `materialize` as a parallel public verb for this boundary.

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

## Astrochicken

Astrochicken is the small probe installation profile under `profiles/astrochicken`:

```text
IPv4          /29, 4 GCP-usable addresses
lifecycle     transient systemd smoke-testing lifecycle
frontends     Nginx execution + Squid egress
Logma         not required
Fatline       no full durable Fatline requirement
serverless    optional Gen1/Gen2 shadow functions
```

The installable profile tool is:

```text
github.com/dash-xd/agni/cmd/astrochicken
```

and its complete preparation surface is:

```bash
astrochicken seed <root>
```

That one command seeds the profile source/configuration and shared Terraform library. The operator does not run a second module-seeding command.

## Gateway

Gateway is the durable installation profile:

```text
IPv4          /28, 12 GCP-usable addresses
lifecycle     persistent Fedora CoreOS + Quadlet at boot
frontends     Nginx + Squid
Logma         required
Fatline       full durable Fatline graph
runtime       persistent Redis/gateway services
```

The existing top-level `terraform/` installation is the migration source for the `/28`, FCOS bootstrap, Nginx/Squid Quadlet, and related durable infrastructure pieces. It is not yet the complete Gateway profile because the full Logma/Fatline runtime has not been moved into that profile.

Do not expose `cmd/gateway seed` until that graph is complete. Once complete, Gateway follows the same one-profile/one-seed contract as Astrochicken; it must never require an operator to layer a separate shared-module command afterward.

## Profile evolution

Astrochicken and Gateway may share implementation without becoming the same profile.

```text
Astrochicken
  small/transient probe policy
      |
      +-- shared regional/network/node/function primitives
      +-- Nginx/Squid config
      `-- transient workload lifecycle

Gateway
  durable gateway policy
      |
      +-- shared regional/network/node primitives
      +-- Nginx/Squid config
      +-- persistent Quadlets
      +-- Logma
      `-- full Fatline runtime
```

Do not implement Gateway as "Astrochicken plus shell flags" when the lifecycle and durable service graph differ materially. Reuse lower-level primitives/config fragments instead.

## Smoke use

```bash
smoke env create probe
smoke env tool add probe github.com/dash-xd/agni/cmd/astrochicken@<exact-sha>
smoke env tool run probe astrochicken seed <root>
smoke env terraform probe --dir <root> -- plan
```

The environment may be called `probe`, `gateway-test`, `us-west1`, or anything else. Profile identity and environment role are orthogonal.

## Change protocol

1. Huram owns exact candidates, credentials, deployment values, evidence, and promotion.
2. Smoke owns generic environment/snapshot/tool/native execution.
3. Agni owns reusable infrastructure primitives and complete installation profiles.
4. Profile HCL/config is authoritative for profile composition.
5. Never duplicate a profile's module dependency graph in Go or shell arguments.
6. Seed the shared Terraform library as an internal implementation detail, not as an operator step.
7. Keep Astrochicken transient and Gateway durable; share primitives, not lifecycle identity.
8. Do not expose an installation-profile command until that profile's promised service graph is complete.
9. Preserve Terraform/Butane/QEMU/gcloud as authoritative native contracts.
10. Use `seed` as common vocabulary without sharing unrelated provider/domain implementations.
