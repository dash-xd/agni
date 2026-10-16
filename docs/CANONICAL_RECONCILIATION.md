# Agni canonical reconciliation gates

This branch derives from `codex/cfxd-dns-txt`. It records the cross-repository reconciliation contract without declaring unqualified deployment behavior complete.

## Ownership

- Huram selects exact SHAs, resolves policy and credentials, owns retained Terraform state locators, qualification evidence, lifecycle authority and promotion.
- Smoke composes executable capabilities and immutable Go workspace snapshots; it invokes native tools and Agni profile seeds. Smoke environment names never select infrastructure profiles or own cloud resources.
- Agni owns reusable GCP/FCOS/network/installation mechanics. Terraform, Butane, systemd and Podman remain authoritative for their native resources and state.
- cfxd owns Cloudflare DNS/xdroute projection in an independently managed Terraform root/state.
- Logma, Skymill, ratelimiter, Probot, Prajapati/Atman and Marai own their package-level behavior and requirements; Agni does not compile semantic capability policy.

## Reconciliation decisions

1. Preserve this branch's profile ownership and idempotent source-seeding rules as the general baseline. Do not merge unrelated branch trees wholesale.
2. Port the generic security-cell placement contract from `codex/prajapati-security-cell` only after checking the current Atman/Prajapati and Marai interfaces. Marai authority is process-local; a stored MRS1 checkpoint is inert. Keep separate application/lifecycle identities, no automatic Marai restart, no permanent lifecycle HTTP endpoint, and caller-owned identity policy. Never equate Redis persistence or VM reboot with authority recovery.
3. Reconcile `codex/gcf-router-control-plane-plan` as a separate generic router-deployment capability: immutable source archive, stable function identity and retained Terraform state, distinct runtime/invoker identities, explicit Gen1/Gen2 adapters. Do not introduce a Go Terraform DSL or make Terraform clone repositories.
4. Reconcile `codex/coreos-production-image` as an independently qualified OS artifact pipeline. Keep OS composition separate from Ignition/Butane and workload Quadlets. Preserve static image verification, then require QEMU and disposable GCP boot evidence before image promotion. Do not silently disable OS updates in retained deployments without Huram-owned rollout policy.
5. Gateway remains incomplete. Do not expose `cmd/gateway seed` or claim durable Fatline qualification until the profile-owned /28 Terraform root, FCOS/Ignition runtime projection, Quadlet boot graph, Nginx/Squid, shared Redis, Logma, Skymill and provider workloads are implemented and tested.

## Runtime deployment contract

```text
Huram exact candidate + resolved policy + retained/disposable intent
  -> Smoke exact workspace/tool composition and native execution
  -> Agni profile seed (one authoritative HCL root)
  -> Terraform plan/apply against caller-owned state locator
  -> FCOS Ignition -> systemd/Quadlet
  -> package-owned runtime services and capability-scoped Redis principals
  -> qualification evidence -> Huram promotion
```

The shared Redis substrate is not a substitute for isolation. Each cryptographic isolation domain has its own Marai process and socket. Package-owned Redis requirements must compile into narrowly scoped principals, with deny probes across worlds and operations. Durable Skymill delivery and Logma lifecycle hints are distinct responsibilities. An exact image/commit plus successful Terraform apply is not runtime qualification.

## Qualification checklist

- Verify branch-to-branch contract compatibility and source ownership; preserve original branch SHAs in the Huram request.
- Unit-test profile seeding, stale managed-source removal, state preservation and Terraform formatting/validation.
- Verify Probe assets are actually projected into the FCOS execution path before claiming frontend readiness.
- Verify image artifact provenance, SELinux, Ignition, Podman, Quadlets and reboot on disposable infrastructure.
- Verify application/lifecycle ACL separation, Marai terminal export and new-era recovery, and denial of automatic authority resurrection.
- Verify shared Redis scoped ACLs, 40 MiB RAM-only noeviction behavior, Skymill crash/reclaim, Logma consumption, and Probot ingress independently.
- Exercise retained create/update/destroy with exact state identity, teardown verification, and Huram-owned evidence before promotion.

This document is a reconciliation specification, not evidence that these gates passed.
