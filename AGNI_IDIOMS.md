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
      +-- exact-source Terraform seeding
      +-- gcloud / Butane / QEMU native boundaries
```

Agni exposes ordinary Go packages and installable Go tools. Smoke is optional: Agni must remain usable directly by Go callers and from the command line.

## Native contracts remain authoritative

Terraform owns `.tf`, providers, variables, state/backends, plan/apply/destroy/output semantics. Butane owns Butane/Ignition transformation. QEMU owns machine/device arguments. gcloud owns Google Cloud CLI semantics.

Do not convert Terraform source into Go DSLs or embed deployment-specific HCL as Go raw strings merely to invoke Terraform.

## Seed is the source-preparation idiom

Use **seed** for the operation that prepares a destination from an exact source/tool. This matches the existing Smoke/ghxd worktree idiom (`github-worktree seed`).

`seed` means:

```text
exact source/tool
      |
      v
copy/select authoritative source unchanged
      |
      v
caller-owned destination/root
```

Do not introduce `materialize` as a parallel public verb or package API for the same operation. `materialize` may describe an implementation detail in external systems, but Agni's user-facing and package vocabulary for source-root preparation is `seed`.

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

## Terraform seed tool

`github.com/dash-xd/agni/terraform` owns embedded generic module assets and the `SeedModules` package API.

The installable tool is:

```text
github.com/dash-xd/agni/cmd/agni-terraform
```

Its composition surface is:

```bash
agni-terraform modules
agni-terraform seed \
  --module regional-network \
  --module regional-cell \
  <terraform-root>
```

The tool only selects and seeds Agni-owned generic modules. It does not run Terraform and does not define an environment or deployment recipe.

Smoke composition therefore uses:

```bash
smoke env tool add <env> github.com/dash-xd/agni/cmd/agni-terraform@<version-or-sha>
smoke env tool run <env> agni-terraform seed --module ... <root>
```

## Smoke boundary

The preferred Smoke integration is environment + ordinary Go tool, not a deployment-specific provider command:

```text
Smoke environment
    +-- exact Go modules
    +-- exact Go tools
    |     `-- agni-terraform
    |
    v
seeded ordinary Terraform composition root
    |
    v
installed terraform executable
```

Provider registries remain appropriate for genuine runtime transport/provider capabilities. Terraform root seeding is a tool concern, not a runtime provider.

## Environment recipes

A named environment such as Astrochicken is not an Agni primitive. It is a composition recipe above Agni that selects generic modules and gives them domain meaning.

```text
Astrochicken recipe
  Terraform root + environment-specific policy
        |
        +-- Smoke environment runtime
        +-- Agni generic seed tool/modules
        `-- Terraform CLI
```

Agni never needs to know the recipe name.

## Terraform migration

For reusable Terraform currently living in Huram, Smoke, or legacy Agni roots:

1. keep deployment/domain policy in the caller-owned root;
2. move only generic implementation into Agni modules;
3. expose generic assets through `agni-terraform seed` when environment composition needs them;
4. keep secrets, project/account values, exact candidates, backend selection, qualification, and promotion outside Agni;
5. preserve Terraform resource/state/backend identity during migration.

## Secret/value boundary

Agni MUST NOT persist deployment credentials or business values. Runtime environment variables and arguments supplied by the caller are ephemeral inputs. Huram remains the authority for injecting credentials and deployment-specific values during qualified execution.
