# Agni Go-first cloud tooling idiom

Agni is the reusable cloud/virtualization implementation layer. It contains generic implementation and native-tool adapters, but no organization-specific credentials, project IDs, regions, domains, tenant names, repository names, or deployment policy values.

## Responsibility

```text
Huram
  exact source/tool identities
  credentials + business/deployment inputs
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
      +-- Terraform asset materialization
      +-- gcloud / Butane / QEMU native boundaries
```

Agni should expose ordinary Go packages and installable Go tools. Smoke is optional: Agni must remain usable directly by Go callers and from the command line.

## Native contracts remain authoritative

Agni composes mature native tools; it does not replace them. Terraform owns `.tf`, providers, variables, state/backends, plan/apply/destroy/output semantics. Butane owns Butane/Ignition transformation. QEMU owns machine/device arguments. gcloud owns Google Cloud CLI semantics.

Do not convert Terraform source into Go DSLs or embed deployment-specific HCL as Go raw strings merely to invoke Terraform.

## Reusable Terraform modules

Reusable infrastructure belongs under `terraform/modules` and must remain free of deployment-domain vocabulary. Current primitives include:

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

## Terraform asset tool

`github.com/dash-xd/agni/terraform` owns the embedded generic module assets and `MaterializeModules` package API.

The installable tool:

```text
github.com/dash-xd/agni/cmd/agni-terraform
```

is the normal environment-composition surface for those assets:

```bash
agni-terraform modules
agni-terraform materialize \
  --module regional-network \
  --module regional-cell \
  <terraform-root>
```

The tool only selects and materializes Agni-owned generic modules. It does not run Terraform and does not define an environment or deployment recipe.

This makes Agni naturally composable as a Smoke environment tool:

```bash
smoke env tool add <env> github.com/dash-xd/agni/cmd/agni-terraform@<version-or-sha>
smoke env tool run <env> agni-terraform materialize --module ... <root>
```

## Smoke boundary

The preferred Smoke integration is now **environment + ordinary Go tool**, not a deployment-specific provider command:

```text
Smoke environment
    |
    +-- exact Go modules
    +-- exact Go tools
    |     `-- agni-terraform
    |
    v
ordinary Terraform composition root
    |
    v
installed terraform executable
```

An older optional Agni Smoke provider may remain temporarily as a compatibility surface while callers migrate, but new Terraform composition should not depend on an Astrochicken-specific provider request. Provider registries remain appropriate for genuine runtime transport/provider capabilities; Terraform asset materialization is a tool concern.

## Environment recipes

A named environment such as Astrochicken is not an Agni primitive. It is a composition recipe above Agni that selects generic modules and gives them domain meaning.

```text
Astrochicken recipe
  Terraform root + environment-specific policy
        |
        +-- Smoke environment runtime
        +-- Agni generic module/tool assets
        `-- Terraform CLI
```

Agni never needs to know the recipe name.

## Terraform migration

For reusable Terraform currently living in Huram, Smoke, or legacy Agni roots:

1. keep deployment/domain policy in the caller-owned root;
2. move only generic implementation into Agni modules;
3. expose generic assets through `agni-terraform` when environment composition needs them;
4. keep secrets, project/account values, exact candidates, backend selection, qualification, and promotion outside Agni;
5. preserve Terraform resource/state/backend identity during migration.

## Secret/value boundary

Agni MUST NOT persist deployment credentials or business values. Runtime environment variables and arguments supplied by the caller are ephemeral inputs. Huram remains the authority for injecting credentials and deployment-specific values during qualified execution.
