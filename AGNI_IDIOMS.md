# Agni Go-first cloud tooling idiom

Agni is the reusable cloud/virtualization build layer. It contains generic implementation and native tool composition, but no organization-specific credentials, project IDs, regions, domains, tenant names, repository names, or deployment policy values.

## Responsibility

```text
Huram
  organization/business inputs + credentials + exact candidate selection
      |
      v
Smoke
  generic Go workspace/tool composition + immutable execution snapshots
      |
      v
Agni
  generic cloud/CoreOS/QEMU build capabilities
      |
      +-- Terraform CLI + reusable .tf/config assets
      +-- gcloud
      +-- Butane/CoreOS
      +-- QEMU
```

Agni should expose ordinary Go packages and installable Go tools. Smoke is optional: a Go programmer must be able to install or import Agni directly.

## Native contracts remain authoritative

Agni wraps mature native tools; it does not replace them. Terraform keeps ownership of `.tf`, state/backends, providers, plan/apply and variable semantics. Butane keeps ownership of Butane/Ignition transformation. QEMU keeps ownership of machine/device arguments. gcloud keeps ownership of Google Cloud CLI semantics.

The root Agni tool is therefore intentionally thin:

```bash
agni terraform ...
agni gcloud ...
agni coreos ...
agni qemu ...
agni exec ...
```

Arguments and environment are forwarded rather than translated into an Agni-specific language.

## Terraform migration

Reusable, non-business-specific Terraform currently living in Huram should move to Agni incrementally. Do not bulk-move modules merely to satisfy this boundary. For each module:

1. separate reusable infrastructure implementation from deployment-specific values;
2. move the generic `.tf` implementation/assets to Agni;
3. keep secrets, tfvars/business values, project/account identifiers, policy decisions and orchestration inputs in Huram;
4. have Huram invoke Agni/Terraform with those values;
5. preserve Terraform state/backend identity during the migration.

Agni may retain its existing `terraform/`, `qemu/`, and build assets while Go packages/tools are layered over them. Compatibility is preferred over gratuitous moves.

## Secret/value boundary

Agni MUST NOT embed or default organization-specific secrets or business deployment values. Environment variables and command arguments supplied by the caller are runtime inputs, not repository configuration.

Smoke MUST NOT embed those values either.

Huram is the authority for injecting them at orchestration time.
