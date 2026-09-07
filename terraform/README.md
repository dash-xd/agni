# Agni Terraform composition

Agni contains reusable Terraform implementation and may also contain standalone Terraform roots. Reusable modules under `terraform/modules` are intentionally free of deployment-domain vocabulary and organization-specific values.

Current reusable modules:

- `regional-network`: one regional dual-stack subnet with caller-selected IPv4 CIDR, including `/29`; Private Google Access is enabled by default and the module reports usable address count after Google Cloud's four reserved addresses.
- `regional-internal-addresses`: caller-named static internal IPv4 reservations from a regional subnet.
- `coreos-node`: indexed Fedora CoreOS instances attached to a supplied subnet; slot capacity derives from subnet size and callers may attach alias IP ranges.
- `regional-cell`: composition of network, optional internal-address reservations, and node modules.
- `cloud-function-v1-http`: generic 1st gen HTTP function with caller-selected source/runtime/identity/ingress and invoker IAM members.
- `cloud-function-v2-http`: generic 2nd gen HTTP function with caller-selected source/runtime/identity/ingress and Cloud Run invoker IAM members.

Function modules do not consume VM subnet addresses. Direct VPC egress remains a separate concern. Static internal reservations likewise carry no application meaning; callers may use them as aliases/VIPs while guest configuration remains caller-owned.

## Seed selected modules

`github.com/dash-xd/agni/terraform` embeds the generic module source and exposes `SeedModules`. The implementation lives in `terraform/seed.go` and only copies caller-selected authoritative `.tf` files into `<root>/modules`.

The installable tool is intentionally short:

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

`tf seed` is independent from Smoke/ghxd worktree seeding. The two share the verb because both prepare an exact-source destination, but Agni performs no Git, repository, ref, object-database, auth, or worktree operations.

The native `terraform` executable remains a separate contract and owns HCL parsing, providers, state, plan/apply/destroy/output semantics.

No reusable module should contain names such as Astrochicken, Farcaster, World, Fatline, or application-specific service topology. Those belong to the caller that composes the generic modules.
