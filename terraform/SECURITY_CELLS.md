# Security cell placement contract

Agni is the host/network substrate for regional security cells. A cell may use the existing Agni VPC, regional subnet, Fedora CoreOS member placement, leader ingress, and Squid egress while higher-level tenant/IAM policy remains outside Agni.

`huram-abi-master` owns the security-cell manifest, lifecycle policy, exact component identity, backup/recovery policy, and deployment evidence. Atman owns identity-based tenant routing. Marai owns one process-local cryptographic authority per isolation domain. Logma owns event distribution and may carry lifecycle signals, but neither Logma nor Pub/Sub owns destruction or backup authority.

Agni metadata and CoreOS bootstrap remain generic: role, leader IP, subnet CIDR, service port, and other host-level placement data may be supplied by Terraform, while tenant registries, caller identities, ACL credentials, live KMS keys, backup policy, and secret/event policy are caller-owned runtime inputs.

## Cryptographic lifetime is the primary cell invariant

A security cell exists to make cryptographic authority lease-bounded:

```text
cell starts
    -> Marai creates/imports live master-key state in process memory
    -> workloads use narrow application crypto capability
    -> cell may remain live for hours/days/months
    -> lifecycle enters terminal quiesce/export phase
    -> optional terminal static snapshot is committed
    -> live Marai process is destroyed
    -> live cryptographic authority no longer exists
```

A host/process crash before a successful terminal export destroys the live authority by design. Agni MUST NOT add Redis persistence, VM-disk persistence, replication, failover, or restart semantics that imply transparent Marai key continuity.

The preferred production default is one isolated cell per tenant. `shared-host` may place several tenant runtimes on one CoreOS member, but each tenant retains a separate Marai process, Unix socket, ACL credential set, live-memory key set, and writable `/run` subtree. Sharing one Marai process across tenants is intentionally unsupported.

## Terminal backup is not ordinary persistence

A final backup is a lifecycle operation, not a background durability feature.

The cell has two valid terminal snapshot classes:

```text
archive-only
  application/static data is copied out
  Marai key material is NOT exported
  encrypted material becomes intentionally unrecoverable after cell death

sealed-recovery
  application/static data is copied out
  Marai exports an explicitly sealed recovery artifact
  artifact is unusable by ordinary runtime identities
  reactivation requires separate recovery authority and a new cell
```

There is deliberately no mode equivalent to "persist Marai state to disk and restart later".

A sealed recovery artifact must not contain plaintext master keys, Redis ACL passwords, or an immediately usable Marai database image. It must be cryptographically sealed to an external recovery authority that is not available to the normal runtime principal. Normal Atman callers, Marai application identities, Farcaster workloads, and function runtime service accounts must not be able to unwrap it.

The exact sealing implementation is outside Agni. A caller may use Google Cloud KMS or another qualified wrapping authority, but the important boundary is:

```text
live cell authority
      !=
recovery authority
```

If the same runtime service account can both use Marai and unwrap the terminal recovery snapshot, the cell no longer has the desired death boundary.

## Lifecycle ordering

The generic terminal sequence is:

```text
running
  -> quiescing
  -> drain/deny new mutating crypto consumers as required
  -> freeze application state boundary
  -> produce static application backup
  -> optionally produce sealed Marai recovery snapshot
  -> hash/manifest backup artifacts
  -> commit backup to caller-selected durable storage
  -> independently verify committed artifact identity
  -> mark terminal export complete
  -> stop Atman ingress
  -> destroy Marai process
  -> destroy remaining cell runtime/host through exact owner
  -> independently verify absence
  -> acknowledge lifecycle completion
```

Destruction MUST NOT occur merely because a shutdown signal was published. Huram/exact deployment state remains the authority for the cell that may be terminated.

If terminal export is required by policy and export fails, destruction fails closed unless the request explicitly authorizes abandonment of recovery. That abandonment is a distinct lifecycle decision and evidence event.

## Restart semantics

Marai process restart is cryptographic death unless the deployment is explicitly performing a qualified sealed-recovery restore into a new authority instance.

Therefore generic service managers must not use restart policies that imply key continuity. A long-running cell may supervise Atman and other stateless components normally, but Marai restart behavior must reflect the configured cell mode:

```text
ephemeral-only
  unexpected Marai exit => cell enters failed/terminal state

sealed-recovery-capable
  unexpected Marai exit => cell enters failed state
  no automatic restore
  explicit recovery workflow may create a new cell/authority
```

Automatic restart plus silent key regeneration is also invalid for a retained cryptographic cell because existing ciphertext would no longer match the new authority while the surrounding deployment might appear healthy.

## Agni versus Huram

Agni owns reusable host mechanics only:

```text
CoreOS/VM placement
network/subnet/egress primitives
container/Quadlet templates
run-scoped tmpfs directories
mount/cgroup/process isolation primitives
backup destination plumbing as generic inputs
lifecycle hooks as generic executable boundaries
```

Huram owns:

```text
which tenant/cell exists
exact Atman/Marai revisions
caller service accounts and audiences
cell deployment_id/state_locator
whether terminal backup is required
archive-only versus sealed-recovery policy
backup destination identity
recovery authority identity
quiesce/export/destroy authorization
qualification and evidence
```

Agni MUST NOT hardcode tenant names, `dashxd` service-account emails, audiences, Marai key IDs, or backup/recovery identities in Butane/Ignition templates.

## Atman placement

Atman is an ingress adapter to a live cryptographic authority. It is not the owner of Marai key lifetime and should not own terminal export policy.

During quiesce, Atman should be able to stop admitting ordinary application crypto requests before Marai export/destruction. Administrative export/restore operations remain on a distinct local/privileged boundary and should not be exposed through the normal tenant HTTP API.

## Smoke and qualification

Smoke may provide local composition/qualification helpers for the lifecycle, but it does not own production policy or durable recovery state.

The minimum useful proof is:

```text
create cell
-> create/use Marai key
-> encrypt known material
-> prove ordinary app cannot export keys
-> quiesce
-> create terminal backup
-> destroy Marai
-> prove old live authority is gone
-> prove ordinary runtime cannot recover snapshot
-> when sealed-recovery is enabled, explicitly authorize recovery
-> create a NEW Marai authority from the sealed artifact
-> prove expected ciphertext can be decrypted
```

For archive-only mode, the final expected proof is instead that the old ciphertext is no longer decryptable after Marai destruction.

See `SECURITY_CELL_LIFECYCLE_PLAN.md` for the implementation sequence.
