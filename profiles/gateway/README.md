# Gateway installation profile

Gateway is the durable Agni installation profile. It is composed from reusable Probe capabilities and shared Agni primitives, then adds Gateway-specific network, lifecycle, and durable service policy.

## Required contract

```text
IPv4          /28, 16 total addresses, 12 GCP-usable addresses
lifecycle     Fedora CoreOS + persistent Quadlet at boot
frontends     Nginx execution + Squid egress
Logma         required
Fatline       selected Logma/Skymill/provider roles; Marai optional
runtime       retained FCOS services; Redis persistence is separately selected
```

## Composition from Probe

Probe is not a parent root that Gateway patches. Probe's `/29` HCL and transient systemd lifecycle remain Probe-specific policy.

Gateway should reuse Probe-owned capabilities only where their contracts remain valid, while supplying its own durable profile root:

```text
shared Agni primitives
        |
        v
Probe reusable capabilities
        |
        +-- Probe profile
        |     /29 + transient lifecycle
        |
        `-- Gateway profile
              /28 + persistent lifecycle
              + Logma
              + Fatline
```

This avoids both duplication and configuration override chains.

## Migration source

The current top-level `terraform/` installation already contains useful Gateway pieces:

- `/28` regional subnet and 12-slot addressing semantics;
- Fedora CoreOS provisioning;
- bootstrap configuration;
- Nginx and Squid Quadlet assets;
- durable boot-time service configuration.

Those pieces should be migrated/recomposed here over Probe/shared Agni building blocks rather than copied into a second independent implementation.

## Completion gate

Do **not** add `cmd/gateway` until this profile contains the complete durable graph promised by the name, including Logma/Fatline and the persistent gateway runtime.

Once complete, its operator surface is exactly one profile seed:

```bash
smoke env create gateway
smoke env tool add gateway github.com/dash-xd/agni/cmd/gateway@<agni-sha>
smoke env tool run gateway gateway seed <root>
smoke env terraform gateway --dir <root> -- plan
```

There must not be a subsequent `tf seed`, module list, or shell-side dependency declaration.

## Deployment reconciliation with Huram Abi

The existing Huram `worktree-automation/.github/workflows/probot-fatline-composition.yml` is the source of local qualification mechanics: exact Smoke ghxd worktree seeding of Probot, Skymill and Logma; run-owned 40 MiB RAM-only noeviction Redis; scoped ACL probes; Nix application image build; and component-owned Quadlet evaluation. The existing `farcaster-gateway-lifecycle-logma-smoke.yml` proves a separate retained FCOS execution precedent, not the installation of this profile. Reuse those contracts; do not create a parallel installer or a new infrastructure DSL.

Huram owns immutable source, request/current-blob authority, credential coverage, Terraform state locator, exact run evidence and promotion. Smoke owns Go tool/workspace composition and ghxd execution. Application Nix flakes own application composition and image/Quadlet outputs. Agni owns generic FCOS placement, Terraform and Ignition projection. The same qualified inputs must work through Actions or local Smoke ghxd; local execution does not grant retained mutation credentials.

A minimal Gateway selects shared Redis, independent Logma and Skymill services and provider roles. Probot and Stonks use the same substrate with distinct scoped credentials. Logma owns live Pub/Sub; Skymill owns durable stream delivery and ACK/reclaim. Neither Probot nor Stonks supervises shared services. Persistent FCOS boot does not make RAM-only Redis durable across Redis loss. Recovery/checkpoint frontier must be independently qualified.

**Marai/Prajapati is optional.** The separate `terraform/leader/security-cell.bu.tmpl` remains a security-cell placement capability, not a Gateway dependency. Do not auto-start Marai or assume its process authority survives restart. The Atman/Prajapati naming/interface difference must be reconciled against exact current component sources before that optional capability is selected.

### Blocking gates

- Materialize the actual Gateway /28 Terraform root, FCOS Ignition, Nginx/Squid assets, independently built Logma/Skymill/provider Quadlets and startup/readiness dependencies.
- Qualify package-owned scope-first ACLs, native Logma consumption, Skymill ACK/crash/reclaim, Probot HMAC/GUID fences and Stonks live versus durable publication using run-owned Redis.
- Prove the same Nix image/Quadlet artifacts locally and on disposable FCOS before obtaining retained-target mutation authority.
- Prove selected public GitHub ingress with the existing Probot raw-body handler; do not assume a Cloudflare Tunnel.
- Verify exact deployment/state identity, restart behavior, teardown and independently recorded Huram evidence before promotion.

Do not add `cmd/gateway seed` or claim deployment qualification until these executable gates pass.
