# Security cell placement contract

Agni is the generic host/network substrate for regional security cells. Huram owns deployment policy, exact component identities, principal/audience policy, lifecycle authorization, checkpoint destinations, recovery authority, and evidence. Prajapati owns authenticated semantic identity/authorization. Logma owns durable Fatline bindings/events/runtime coordination. Marai owns one process-local cryptographic authority per isolation domain.

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
    +-- Logma
    |     durable Fatline binding/event runtime
    |
    +-- Prajapati
    |     semantic principal + audience + action + resource enforcement
    |     application-only Marai identity
    |
    `-- Marai process
          private Unix socket
          process-memory master keys
          no network
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
exact Prajapati/Logma/Marai revisions
tenant semantic names
normalized principals and audiences
provider-specific identity materialization
backup policy and destination
MRS1 recovery public/private authority
quiesce/export/recovery authorization
evidence and retained lifecycle state
```

Agni MUST NOT hardcode organization service accounts, Ed25519 principals, SPIFFE identities, tenant names, audiences, key IDs, project-specific recovery identities, or business profile names.

The identity boundary is intentionally compiled above Agni:

```text
Huram semantic principal
        |
        v
provider/compiler materialization
        |
        +-- GCP      -> gcp-sa:world@project.iam.gserviceaccount.com
        +-- local    -> ed25519:logma/world-17
        `-- future   -> spiffe://xd.run/farcaster/world-17
        |
        v
Prajapati principal + exact audience/action/resource policy
```

Agni only places the resulting registry/config artifacts and runtime processes.

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

Prajapati is stateless relative to Marai authority and may restart. Its readiness must require `KMS.STATUS == active`; a live Redis process in `BOOTSTRAP`, `QUIESCED`, `EXPORTED`, or `DEAD` is not a ready application KMS.

Prajapati's gateway policy is provider-neutral:

```text
opaque credential
    -> configured identity verifier(s)
    -> normalized Principal { ID, Issuer, Audience }
    -> exact principal binding
    -> exact audience/action/resource authz.Policy
    -> Marai application capability
```

Google IAM is one possible verifier/materialization, not an Agni dependency. A cell may use Ed25519 or another qualified Prajapati identity adapter without changing the Agni host substrate.

## Application versus lifecycle credentials

Agni materializes two physically separate runtime directories:

```text
/run/agni-security-cell/marai-app/
    redis.sock
    app.password

/run/agni-security-cell/marai-admin/
    admin.password
```

Prajapati receives only `marai-app/` as a read-only bind mount. It cannot read `admin.password`. The Marai container receives both because it must bootstrap the two Redis ACL identities internally.

The steady-state application path is:

```text
workload -> Prajapati -> marai-app -> Marai
```

The lifecycle path is separate:

```text
Huram/operator
    -> ephemeral local lifecycle executor on the target
    -> marai-admin + redis.sock
    -> KMS.CREATE/ROTATE/QUIESCE/EXPORT/ZEROIZE
```

There is no permanent lifecycle HTTP endpoint. `KMS.IMPORT` remains bootstrap/recovery-only and is not granted to steady-state `marai-admin`.

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

## Generic CoreOS template

`terraform/leader/security-cell.bu.tmpl` is intentionally one-cell and policy-free. The caller supplies:

```text
MARAI_IMAGE
PRAJAPATI_IMAGE
REGISTRY_HOST
PRAJAPATI_TENANT_REGISTRY_B64
```

The Prajapati registry is non-secret deployment policy that already names the cell-local socket `/run/marai/redis.sock`, the `marai-app` identity, exact audiences, normalized principals, and immutable auth policy bindings. Agni does not construct or interpret those semantics itself.

Provider-specific identity material such as an Ed25519 public-key registry may be injected as another caller-owned read-only runtime artifact when that verifier is selected. Private signing material and recovery private authority never belong in Agni templates or Terraform state.

The host generates ephemeral Marai ACL passwords under `/run`; they are not Terraform inputs and do not belong in Compute Engine custom metadata. Artifact Registry login also uses an auth file under `/run`, avoiding Podman's ordinary persistent auth location.

## Qualification boundary

The escalation order is:

```text
Marai repository production-image tests
    -> two-process MRS1 export/import test
    -> Prajapati identity/authz tests
    -> Logma binding + ratelimiter redisacl tests
    -> Smoke local Logma + Prajapati + Marai composition
    -> Huram exact-SHA staging/evidence
    -> disposable Agni/CoreOS target
    -> retained deployment only after those gates
```

Smoke owns generic composition and behavioral qualification. Huram owns target authority and evidence. Agni provides the target substrate.

The first local proof should include `ed25519:logma/world-17`, a callback principal, and `ed25519:gateway/world-17`, plus both positive and negative action/resource decisions. It must also prove that Prajapati cannot exercise Marai lifecycle authority.

Logma/NQC may later accelerate checkpoint discovery and convergence, but Pub/Sub is never checkpoint authority and NQC does not make Marai active-active. The first distributed model remains one authoritative mutation lineage with immutable checkpoints and anti-entropy repair.
