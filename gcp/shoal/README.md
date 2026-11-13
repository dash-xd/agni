# GCP Shoal: first integration candidate

This is a **static, non-deploying** selection contract for the existing
Agni GCP Terraform entry points; it is not a new provider or provisioning
framework. The local QEMU/Podman Shoal qualification remains historical
evidence and is not an implementation dependency for GCP.

## Candidate

- One regional ingress **Farcaster**, selected from `terraform/leader`.
  The existing module declares a reserved external address, Cloudflare
  HTTPS ingress, and Squid on TCP 3128 for selected private source CIDRs.
- One private **World**, selected from `terraform` with `vm_slots=[0]`.
  The existing module points member egress at the leader's private IP
  through its remote state and permits leader-to-member service traffic.
- Target after integration qualification: one Farcaster and seven Worlds
  on the regional Shoal VPC. This does **not** select eight live VMs today.

The source revision is always a specific Git commit. Execution may be
initiated from Huram/Smoke in GitHub Actions, Gitea, Cloud Shell, GCE,
or a local Nix environment; the candidate has no host-path assumptions.

## Before any GCP apply

Reconcile actual GCP resources and Terraform state, rather than creating
a second Shoal network from defaults. In particular:

1. Verify the existing leader and member subnet names, CIDRs, regions and
   ownership; both Terraform roots currently declare separate subnets.
2. Verify the selected instance template and its actual Spot scheduling.
   The current Terraform roots do **not** assert `provisioning_model=SPOT`
   themselves; the instance templates determine this.
3. Reconcile state backend and provider revision pins with the current
   Huram/FireKV workflow. These older roots still refer to GCS backends.
4. Verify reserved external address and Cloudflare DNS records before
   writing. Do not create a second public IP or modify live DNS by
   running this static candidate.
5. Qualify private communication, Squid access and denied direct egress
   for IPv4 and IPv6 in the real VPC. An HTTP_PROXY environment variable
   alone does not enforce egress restriction.
6. Build and test the real Fatline workload on Farcaster separately.
   The current leader bootstrap has Nginx/Squid but is not a successful
   Redis/Logma/Skymill runtime qualification.

Local static check (no cloud credentials required):

```sh
python3 -m unittest discover -s gcp/shoal -p 'test_*.py'
```

This contract intentionally does not dispatch Terraform or create a
new executable management layer. Provider operations and exact worktree
selection should remain in the existing Huram/Smoke automation path.
