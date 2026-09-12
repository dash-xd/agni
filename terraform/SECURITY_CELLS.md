# Security cell placement contract

Agni is the generic host/network substrate for regional security cells. Huram owns deployment policy, exact component identities, caller/audience policy, lifecycle authorization, checkpoint destinations, recovery authority, and evidence. Atman owns authenticated application ingress. Marai owns one process-local cryptographic authority per isolation domain.

The primary invariant is:

```text
running Marai process = active cryptographic authority
stored MRS1 object     = inert recovery state
```

Redis persistence, Redis replication, VM-disk persistence, service-manager restart, and ordinary host restart must never imply Marai authority continuity.

## Placement

The preferred shape is one Marai process per cryptographic isolation domain:

```text
Agni/CoreOS host
    |
    +-- Marai process
    |     private Unix socket
    |     process-memory master keys
    |     no network
    |
    `-- Atman
          authenticated application ingress
          application-only Marai identity
```

A shared physical host may carry multiple cells later, but each cell must keep a separate Marai process, socket, ACL identities, writable `/run` subtree, lifecycle identity, and checkpoint lineage. A shared Marai process is not a hostile-tenant boundary and is intentionally outside the current contract.

## Agni versus Huram

Agni owns reusable mechanics only:

```text
CoreOS / VM placement
network / subnet / egress primitives
container and systemd/Quadlet templates
run-scoped directories
Unix-socket placement
container isolation
caller-materialized registry/config injection
```

Huram owns:

```text
cell/deployment identity
exact Atman/Marai revisions
tenant semantic names
callers and audiences
backup policy and destination
MRS1 recovery public/private authority
quiesce/export/recovery authorization
evidence and retained lifecycle state
```

Agni MUST NOT hardcode organization service accounts, tenant names, audiences, key IDs, project-specific recovery identities, or business profile names.

## Lifecycle semantics

Marai's qualified lifecycle is:

```text
BOOTSTRAP
    -> ACTIVE
    -> QUIESCED
    -> optional terminal MRS1 EXPORT
    -> EXPORTED
    -> ZEROIZE
    -> DEAD
```

Unexpected Marai process exit is authority loss. Generic service management therefore uses no automatic Marai restart. A recovered authority is created explicitly from an authenticated MRS1 checkpoint and has a new process instance and a new authority era.

Atman is stateless relative to Marai authority and may restart. Its readiness must require `KMS.STATUS == active`; a live Redis process in `BOOTSTRAP`, `QUIESCED`, `EXPORTED`, or `DEAD` is not a ready application KMS.

## Terminal backup classes

A caller may select:

```text
archive-only
    application/static state is exported
    Marai authority is not checkpointed
    old Marai-only ciphertext becomes permanently unusable after death

sealed-recovery
    application/static state is exported
    Marai produces terminal MRS1 using an external recovery public key
    stored MRS1 is inert
    explicit recovery authority may create a NEW Marai authority later
```

There is deliberately no "persist Redis and restart it later" mode.

The ordinary application principal cannot export/import authority. The steady-state Marai cryptographic administrator may create/rotate/quiesce/export/zeroize but must not be able to grant itself `KMS.IMPORT`. Recovery policy/root authority is separate from steady-state administration.

## Generic CoreOS template

`terraform/leader/security-cell.bu.tmpl` is intentionally one-cell and policy-free. The caller supplies:

```text
MARAI_IMAGE
ATMAN_IMAGE
REGISTRY_HOST
ATMAN_TENANT_REGISTRY_B64
```

The Atman registry is non-secret deployment policy that already names the cell-local socket `/run/marai/redis.sock`, the `marai-app` identity, audiences, and callers. Agni does not construct those semantics itself.

The host generates ephemeral Marai ACL passwords under `/run`; they are not Terraform inputs and do not belong in Compute Engine custom metadata. Artifact Registry login also uses an auth file under `/run`, avoiding Podman's ordinary persistent auth location.

## Qualification boundary

The escalation order is:

```text
Marai repository production-image tests
    -> two-process MRS1 export/import test
    -> Atman repository tests
    -> Smoke cross-repository composition
    -> Huram exact-SHA local staging
    -> disposable Agni/CoreOS target
    -> retained deployment only after those gates
```

Smoke owns generic composition and behavioral qualification. Huram owns target authority and evidence. Agni provides the target substrate.

Logma/NQC may later accelerate checkpoint discovery and convergence, but Pub/Sub is never checkpoint authority and NQC does not make Marai active-active. The first distributed model remains one authoritative mutation lineage with immutable checkpoints and anti-entropy repair.
