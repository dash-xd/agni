# Agni Terraform composition

Agni contains reusable Terraform implementation and may also contain standalone Terraform roots. Reusable modules under `terraform/modules` are intentionally free of deployment-domain vocabulary and organization-specific values.

Current reusable modules:

- `regional-network`: one regional dual-stack subnet with caller-selected IPv4 CIDR, including `/29`; Private Google Access is enabled by default and the module reports the usable address count after Google Cloud's four reserved addresses.
- `regional-internal-addresses`: caller-named static internal IPv4 reservations from a regional subnet. These are generic reservations that callers may later use as VM alias `/32`s, internal forwarding VIPs, or other service identities; the module does not assign application meaning.
- `coreos-node`: indexed Fedora CoreOS instances attached to a supplied subnet; slot `0` begins at host offset `2`, valid slot count derives from the subnet size, and callers may attach alias IP ranges to a node.
- `regional-cell`: composition of the network, optional internal-address reservations, and node modules.
- `cloud-function-v1-http`: generic 1st gen HTTP function with caller-selected source/runtime/identity/ingress and non-authoritative invoker IAM members.
- `cloud-function-v2-http`: generic Cloud Run function (2nd gen) with caller-selected source/runtime/identity/ingress and `roles/run.invoker` bindings on the underlying Cloud Run service.

The function modules require the caller to choose an ingress policy; Agni does not impose internal-only, load-balanced, or public policy. They do not attach functions to the VM subnet or consume its addresses. Direct VPC egress for function-to-VPC traffic is a separate concern and is intentionally not implied by these modules.

Static internal address reservations are likewise separate from serverless addressing. A caller may reserve addresses from the primary subnet and assign them as `/32` alias ranges to a VM to create stable application-owned service identities, but the guest OS/workload remains responsible for configuring and listening on those aliases.

## Seed selected modules

The Go package `github.com/dash-xd/agni/terraform` embeds these module files and exposes `SeedModules`. Seeding copies only caller-selected authoritative `.tf` source into a caller-owned Terraform root; it is not a second Terraform language.

The CLI equivalent is:

```bash
agni-terraform seed \
  --module regional-network \
  --module regional-cell \
  <terraform-root>
```

`seed` is the same exact-source destination-preparation idiom used by Smoke/ghxd worktrees. Do not introduce `materialize` as a parallel public term for this operation.

No reusable module should contain names such as Astrochicken, Farcaster, World, Fatline, or application-specific service topology. Those belong to the caller that composes the generic modules.
