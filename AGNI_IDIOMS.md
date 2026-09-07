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

## Reusable regional Terraform

Reusable regional infrastructure belongs under `terraform/modules` and must remain free of deployment-domain naming.

The current primitive stack is:

```text
regional-network
    caller-selected regional IPv4 CIDR
    optional dual stack
    Private Google Access is caller-configurable
    reports usable address capacity

coreos-node
    indexed Fedora CoreOS instances
    slot -> stable internal IPv4 derived from subnet CIDR
    caller-supplied metadata/tags/service identity/user-data

regional-cell
    regional-network + coreos-node composition

cloud-function-v1-http
    caller-selected 1st-gen HTTP function
    caller-selected ingress + invoker identities

cloud-function-v2-http
    caller-selected Cloud Run function
    caller-selected ingress + Cloud Run invoker identities
```

Google Cloud reserves the first two and last two IPv4 addresses in each primary subnet. Agni therefore derives usable node capacity from the CIDR rather than assuming a fixed `/28` or a fixed twelve-node topology. A `/29` yields four usable node slots; a `/28` yields twelve. Slot `0` starts at host offset `2`.

The modules MUST NOT assign meanings such as gateway, world, farcaster, astrochicken, Fatline, Logma, or application roles. Callers assign workload and topology meaning through ordinary Terraform inputs. A two-node `/29` smoke probe and a twelve-node `/28` regional deployment can therefore share the same implementation modules.

Serverless functions are not address slots in the VM subnet. Function source, runtime, ingress, IAM, and lifecycle are separate reusable inputs. In particular, Agni MUST NOT silently select `ALLOW_INTERNAL_ONLY`; a caller such as Smoke can choose it when the deployment requires VPC-only invocation. Direct VPC egress from serverless resources back into a VPC is also a separate capability and must not be implied merely because a function is regional or internally invokable.

`github.com/dash-xd/agni/terraform` embeds reusable module files and materializes only caller-selected modules. This is an asset-selection mechanism, not a second deployment language.

## Smoke composition boundary

Agni may provide an optional package for Smoke composition. That package may register a narrow provider with Smoke and may blank-import Smoke's corresponding command package so a single Go import adds the capability.

The Agni side of this contract remains generic:

```text
caller-owned Terraform root
        |
        | selects module names + Terraform args
        v
Agni Smoke provider
        |
        +-- materialize selected Agni modules
        +-- invoke `terraform -chdir=<workspace> ...`
```

Agni MUST NOT define Smoke-domain recipes such as Astrochicken. Smoke owns those names, lifecycle policy, representative topology choices, serverless-shadow policy, and outside-vs-environment behavior. Agni only provides the generic infrastructure implementation selected by the caller.

## Terraform migration

Reusable, non-business-specific Terraform currently living in Huram or legacy Agni roots should move to reusable modules incrementally. Do not bulk-move modules merely to satisfy this boundary. For each module:

1. separate reusable infrastructure implementation from deployment-specific values;
2. move the generic `.tf` implementation/assets to Agni modules;
3. keep secrets, tfvars/business values, project/account identifiers, policy decisions and orchestration inputs with the caller;
4. have the caller invoke Agni/Terraform with those values;
5. preserve Terraform state/backend identity during the migration.

Agni may retain existing standalone `terraform/`, `qemu/`, and build assets while Go packages/tools are layered over them. Compatibility is preferred over gratuitous moves, but new reusable code must follow the generic module boundary.

## Secret/value boundary

Agni MUST NOT embed or default organization-specific secrets or business deployment values. Environment variables and command arguments supplied by the caller are runtime inputs, not repository configuration.

Smoke MUST NOT embed those values either.

Huram is the authority for injecting them at orchestration time.
