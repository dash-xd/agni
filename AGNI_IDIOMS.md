# Agni Go-first cloud tooling idiom

Agni is the reusable cloud/virtualization implementation and installation-profile layer. It contains generic infrastructure primitives plus complete installation profiles, but no organization credentials, promotion authority, or Huram qualification policy.

## Responsibility

```text
Huram
  exact source/profile identities
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
Agni profiles
  complete installation recipes
      |
      +-- profile config/policy
      +-- profile lifecycle/workload policy
      `-- shared Agni infrastructure modules
              |
              v
       Terraform / Butane / QEMU / gcloud
```

Smoke environment names are local/operator labels. They never implicitly select an Agni profile.

## Native contracts remain authoritative

Terraform owns `.tf`, providers, variables, state/backends, plan/apply/destroy/output semantics. Butane owns Butane/Ignition transformation. QEMU owns machine/device arguments. gcloud owns Google Cloud CLI semantics.

Do not replace those languages with Go DSLs merely to invoke them.

## Profiles own dependency selection

A profile owns both its root configuration and the exact shared modules that configuration imports.

```text
profile seed
    |
    +-- root .tf/config files
    `-- shared modules required by that root
```

The operator MUST NOT restate this dependency graph with a second command such as:

```text
tf seed --module regional-cell --module ...
```

That duplicates source-of-truth information already present in the profile.

`github.com/dash-xd/agni/terraform` may expose package APIs such as `SeedModules` for profile implementations, but there is no public `cmd/tf` composition step. Shared Terraform modules are an internal library surface for profiles and Go callers.

## Seed is a shared verb, not a shared implementation

Use `seed` for exact-source destination preparation, while keeping each domain implementation independent.

```text
ghxd/worktree seed
    Git repository + exact SHA
    -> Git object/ref/worktree operations

Agni profile seed
    embedded profile config + selected shared modules
    -> filesystem preparation of a complete installation root
```

Agni MUST NOT import or call ghxd/worktree seeding merely because both operations use the verb `seed`.

Do not introduce `materialize` as a parallel public verb for the same operation.

## Shared Terraform primitives

Reusable infrastructure belongs under `terraform/modules` and should remain free of installation-specific vocabulary where practical. Current primitives include:

```text
regional-network
regional-internal-addresses
coreos-node
regional-cell
cloud-function-v1-http
cloud-function-v2-http
```

Serverless functions are not VM subnet slots. Function ingress, IAM, source/runtime, and VPC egress remain explicit profile/caller concerns.

## Astrochicken profile

Astrochicken is the small probe installation profile and lives under `profiles/astrochicken`.

Its contract is intentionally distinct from Gateway:

```text
IPv4          /29, 4 GCP-usable addresses
lifecycle     transient systemd smoke-testing idiom
frontends     Nginx execution + Squid egress
Logma         not required
Fatline       no full Fatline
serverless    optional Gen1/Gen2 shadow functions
```

The installable tool is:

```text
github.com/dash-xd/agni/cmd/astrochicken
```

Use:

```bash
astrochicken seed <root>
```

That single operation writes the Astrochicken root and all shared Agni modules imported by it.

## Gateway profile

Gateway is the durable installation profile that the larger existing Agni root is converging toward:

```text
IPv4          /28, 12 GCP-usable addresses
lifecycle     persistent Fedora CoreOS + Quadlet at boot
frontends     Nginx + Squid
Logma         required
Fatline       full durable Fatline graph
runtime       persistent Redis/gateway services
```

The existing top-level `terraform/` root already contains the `/28` network and persistent FCOS/Quadlet bootstrap pieces and is the migration source for Gateway. Treat it as an installation root, not as a generic `tf` abstraction.

Do not expose `cmd/gateway seed` until the complete durable Fatline/Logma runtime is represented by that profile; the command name must imply a complete gateway installation rather than a partial skeleton.

## Smoke boundary

Preferred composition is one exact profile tool per installation recipe:

```bash
smoke env create probe
smoke env tool add probe github.com/dash-xd/agni/cmd/astrochicken@<exact-sha>
smoke env tool run probe astrochicken seed <root>
smoke env terraform probe --dir <root> -- plan
```

No profile name belongs in Smoke core, and no separate module-enumeration command belongs in the operator path.

## Environment-role flexibility

Recipe identity and environment role are orthogonal.

```text
profile identity   Astrochicken / Gateway / future installation design
environment name   probe / gateway-test / us-west1 / arbitrary local role
```

A profile may be used by many environments. An environment may accumulate additional tools while a design evolves. Environment names must not become hidden policy or dependency selectors.

## Secret/value boundary

Agni MUST NOT persist deployment credentials or Huram business values. Runtime variables/arguments supplied by callers are ephemeral inputs. Huram remains authority for exact candidates, credentials, backend/tfvars, evidence, and promotion.

## Change protocol

1. Put exact candidate selection, credentials, deployment values, evidence, and promotion in Huram.
2. Put generic environment/snapshot/tool/native execution in Smoke.
3. Put reusable infrastructure primitives and complete installation profiles in Agni.
4. Make each profile own its root configuration and shared-module selection.
5. Never require operators to restate a profile's module dependency graph.
6. Keep profile lifecycle policy explicit: transient probe behavior and durable Gateway behavior are different designs.
7. Preserve Terraform/Butane/QEMU/gcloud as authoritative native contracts.
8. Use `seed` for preparation without sharing unrelated seed implementations across providers/domains.
9. Preserve exact source identity and qualification evidence across migrations.
