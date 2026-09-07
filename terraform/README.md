# Agni Terraform shared library

Agni contains reusable Terraform implementation under `terraform/modules`. These modules are intentionally free of installation-profile vocabulary and organization-specific values where practical.

Current reusable modules:

- `regional-network`: one regional dual-stack subnet with caller-selected IPv4 CIDR; Private Google Access is enabled by default and usable count reflects Google Cloud's reserved addresses.
- `regional-internal-addresses`: caller-named static internal IPv4 reservations from a regional subnet.
- `coreos-node`: indexed Fedora CoreOS instances attached to a supplied subnet; slot capacity derives from subnet size and callers may attach alias IP ranges.
- `regional-cell`: composition of network, optional internal-address reservations, and node modules.
- `cloud-function-v1-http`: generic 1st gen HTTP function with caller-selected source/runtime/identity/ingress and invoker IAM members.
- `cloud-function-v2-http`: generic 2nd gen HTTP function with caller-selected source/runtime/identity/ingress and Cloud Run invoker IAM members.

Function modules do not consume VM subnet addresses. Direct VPC egress remains a separate concern. Static internal reservations likewise carry no application meaning.

## Profile integration

`github.com/dash-xd/agni/terraform` embeds the shared module library and exposes `Seed(root)` for Agni profile implementations and direct Go callers.

`Seed(root)` copies the complete shared library beneath `<root>/modules`. It does not select a profile's dependencies. The profile's ordinary HCL is authoritative for which modules are imported:

```hcl
module "region" {
  source = "./modules/regional-cell"
}
```

This deliberately avoids a second Go/shell dependency manifest.

There is no public `cmd/tf` installation-composition step. Operators select a complete profile such as Astrochicken and run that profile's single seed operation.

The shared-library seed implementation is independent from Smoke/ghxd worktree seeding. It performs no Git, repository, ref, object-database, authentication, or worktree operations.

The native `terraform` executable remains authoritative for HCL parsing, module resolution, providers, state, plan/apply/destroy/output semantics.

No reusable module should contain names such as Astrochicken, Gateway, Farcaster, World, Fatline, or application-specific service topology. Those belong to profile HCL/configuration above this library.
