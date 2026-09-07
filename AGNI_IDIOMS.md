# Agni Go-first cloud tooling idiom

Agni is the reusable cloud/virtualization implementation layer. It contains generic implementation and native-tool adapters, but no organization-specific credentials, project IDs, regions, domains, tenant names, repository names, or deployment policy values.

## Responsibility

```text
Huram
  exact source/tool identities
  credentials + deployment inputs
  qualification + promotion
      |
      v
Smoke
  named Go workspaces/tool sets
  immutable environment snapshots
  generic child execution
      |
      v
Agni tools/packages
  generic cloud/CoreOS/QEMU/Terraform implementation
      |
      +-- reusable Terraform .tf modules
      +-- Terraform module seeding
      +-- gcloud / Butane / QEMU native boundaries
```

Agni exposes ordinary Go packages and installable Go tools. Smoke is optional: Agni must remain usable directly by Go callers and from the command line.

## Native contracts remain authoritative

Terraform owns `.tf`, providers, variables, state/backends, plan/apply/destroy/output semantics. Butane owns Butane/Ignition transformation. QEMU owns machine/device arguments. gcloud owns Google Cloud CLI semantics.

Do not convert Terraform source into Go DSLs or embed deployment-specific HCL as Go raw strings merely to invoke Terraform.

## Seed is a shared verb, not a shared implementation

Use **seed** for exact-source destination preparation, but keep each domain's seed implementation independent.

```text
ghxd/worktree seed
    Git repository + exact SHA
    -> Git object/worktree operations
    -> detached source worktree

Agni Terraform seed
    embedded Agni Terraform module source
    -> filesystem copy/select operations
    -> caller-owned Terraform modules/
```

Agni MUST NOT import or call Smoke `ghxd/worktree` seeding merely because both operations use the verb `seed`. Agni Terraform seeding performs no Git checkout, object-database sharing, role-ref handling, repository auth, or worktree lifecycle.

Do not introduce `materialize` as a parallel public verb or package API for the same source-preparation operation.

## Reusable Terraform modules

Reusable infrastructure belongs under `terraform/modules` and remains free of deployment-domain vocabulary. Current primitives include:

```text
regional-network
regional-internal-addresses
coreos-node
regional-cell
cloud-function-v1-http
cloud-function-v2-http
```

The modules MUST NOT assign meanings such as gateway, world, Farcaster, Astrochicken, Fatline, Logma, Nginx, Squid, or serverless-shadow policy. Callers assign those meanings through ordinary Terraform roots and inputs.

Serverless functions are not VM subnet address slots. Function ingress, IAM, source/runtime, and VPC egress are separate caller-owned concerns. Agni MUST NOT silently select internal-only ingress.

## Terraform seed package and tool

The package:

```text
github.com/dash-xd/agni/terraform
```

owns Agni's embedded generic module source and the `SeedModules` API. Its implementation lives in `terraform/seed.go` to make the source-preparation boundary explicit.

The installable CLI is intentionally short:

```text
github.com/dash-xd/agni/cmd/tf
```

Use:

```bash
tf modules

tf seed \
  --module regional-network \
  --module regional-cell \
  <terraform-root>
```

`tf` does not run Terraform. The name is deliberately distinct from the native `terraform` executable: `tf` seeds Agni-owned source; `terraform` parses/plans/applies it.

Smoke composition therefore uses:

```bash
smoke env tool add <env> github.com/dash-xd/agni/cmd/tf@<version-or-sha>
smoke env tool run <env> tf seed --module ... <root>
```

## Smoke boundary

The preferred Smoke integration is environment + ordinary Go tool, not a deployment-specific provider command:

```text
Smoke environment
    +-- exact Go modules
    +-- exact Go tools
    |     `-- tf
    |
    v
seeded ordinary Terraform composition root
    |
    v
installed terraform executable
```

Provider registries remain appropriate for genuine runtime transport/provider capabilities. Terraform module seeding is a tool concern, not a runtime provider.

## Environment recipes

A named environment such as Astrochicken is not an Agni primitive. It is a composition recipe above Agni that selects generic modules and gives them domain meaning.

```text
Astrochicken recipe
  Terraform root + environment-specific policy
        |
        +-- Smoke environment runtime
        +-- Agni `tf` seed tool/modules
        `-- Terraform CLI
```

Agni never needs to know the recipe name.

## Terraform migration

For reusable Terraform currently living in Huram, Smoke, or legacy Agni roots:

1. keep deployment/domain policy in the caller-owned root;
2. move only generic implementation into Agni modules;
3. expose generic modules through `tf seed` when environment composition needs them;
4. keep secrets, project/account values, exact candidates, backend selection, qualification, and promotion outside Agni;
5. preserve Terraform resource/state/backend identity during migration.

## Secret/value boundary

Agni MUST NOT persist deployment credentials or business values. Runtime environment variables and arguments supplied by the caller are ephemeral inputs. Huram remains the authority for injecting credentials and deployment-specific values during qualified execution.
