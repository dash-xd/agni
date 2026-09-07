# Agni Terraform composition

Agni contains reusable Terraform implementation and may also contain standalone Terraform roots. Reusable modules under `terraform/modules` are intentionally free of deployment-domain vocabulary and organization-specific values.

Current reusable modules:

- `regional-network`: one regional dual-stack subnet with an IPv4 `/28`; it exposes the twelve GCE-usable IPv4 addresses as stable slots `0..11`.
- `coreos-node`: indexed Fedora CoreOS instances attached to a supplied subnet; workload meaning is supplied by the caller through metadata, tags, service identity, and Ignition/user-data.
- `regional-cell`: composition of the network and node modules.

The Go package `github.com/dash-xd/agni/terraform` embeds these module files and lets callers materialize only the modules they selected. This is the integration surface used by optional Smoke composition; it is not a second Terraform configuration language.

No reusable module should contain names such as Astrochicken, Farcaster, World, Fatline, or application-specific service topology. Those belong to the caller that composes the generic modules.
