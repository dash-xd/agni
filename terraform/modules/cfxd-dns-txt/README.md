# cfxd DNS TXT

This module is Agni's Terraform projection for durable Cloudflare TXT records produced by the cfxd/xdroute DNS contract.

The boundary is intentional:

- `xdroute` defines and serializes the provider-neutral DNS contract.
- `cfxd` adapts desired records for Cloudflare-oriented workflows.
- this Terraform module owns durable Cloudflare DNS reconciliation and state.
- Cloudflare DNS contains discovery metadata only; secrets do not belong in these records.

The module does not know Logmash, Axiom, or other service-specific semantics. Callers provide already-rendered TXT owner names and content.

## Example

```hcl
module "cfxd_dns_txt" {
  source = "./modules/cfxd-dns-txt"

  zone_id = var.cloudflare_zone_id

  records = {
    logmash_axiom_us_east = {
      name    = "_axiom._callback.logmash.xd.run"
      content = "xd-route=v1;region=us-east;edge=us-east-1.aws;host=us-east-1.aws.edge.axiom.co"
      ttl     = 1
      comment = "Managed by Agni Terraform from the cfxd/xdroute contract"
      tags    = ["managed-by:agni", "owner:cfxd"]
    }
  }
}
```

Multiple map entries may use the same DNS owner name. Cloudflare then exposes them as an RRset; xdroute consumers must treat those records as alternatives and must not infer preference from DNS ordering.

For normal operation, generate the `records` value from the Go `xdroute` representation rather than duplicating its serialization rules in HCL.
