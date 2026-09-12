# Security-cell lifecycle implementation plan

This plan reflects the current Marai/Atman/Huram/Smoke design rather than the older tenant-KMS experiment.

The target property is:

```text
running process
    = active cryptographic authority

process dies without verified terminal export
    = authority is gone

stored MRS1
    = inert recovery state, not active authority
```

## Implemented component contract

Marai now provides the local authority state machine:

```text
BOOTSTRAP
    -> ACTIVE
    -> QUIESCED
    -> EXPORTED
    -> DEAD
```

with:

```text
KMS.CREATE
KMS.ROTATE
KMS.STATUS
KMS.QUIESCE
KMS.EXPORT
KMS.IMPORT
KMS.ZEROIZE
```

Application Redis Functions remain limited to encrypt/decrypt/generate-data-key.

MRS1 is a versioned, canonical, libsodium-sealed authority checkpoint. Import is valid only into a fresh empty BOOTSTRAP process and creates a new authority era/new process instance. Redis RDB/AOF and Redis replication remain disabled and irrelevant to recovery.

The managed Marai ACL split is:

```text
application
  application Functions + exact native helpers + status

steady-state cryptographic admin
  create / rotate / status / quiesce / export / zeroize
  no application crypto
  no import
  no ACL policy mutation

recovery/bootstrap authority
  materialized separately for explicit recovery
```

Atman remains application ingress only. Its readiness is tied to `KMS.STATUS == active`; lifecycle administration is not exposed over the tenant HTTP API.

## Implemented Agni correction

The generic CoreOS template now:

- contains no tenant semantic names;
- contains no organization service-account emails or audiences;
- accepts a caller-materialized Atman tenant registry;
- hosts one Marai authority per template instance;
- uses `Restart=no` for Marai;
- allows Atman to restart as stateless ingress;
- generates Marai ACL credentials only under `/run`;
- stores Artifact Registry auth only under `/run`;
- does not place recovery material in Terraform or Compute Engine metadata.

The leader module also no longer supplies an organization-specific service-account default.

## Next qualification slice

Qualification proceeds in this order:

```text
Marai repository production-image tests
    -> MRS1 two-process recovery test
    -> Atman component tests
    -> Smoke composition contract
    -> Huram exact-SHA local staging
    -> disposable Agni/CoreOS cell
```

The Huram local staging test must prove at minimum:

```text
exact Marai SHA
exact Atman SHA
managed ACL separation
Marai ACTIVE
Atman ready
local privileged QUIESCE
Redis process still live
Marai QUIESCED
Atman not ready
```

A target-backed Agni test then adds:

```text
render generic Butane with caller registry
boot disposable CoreOS cell
prove no transparent Marai restart
exercise terminal MRS1 export
persist/verify an immutable checkpoint artifact
zeroize live authority
destroy exact target
verify absence
```

No retained cell should be promoted until this disposable path is green.

## Huram lifecycle request

The eventual control-plane request should distinguish operations rather than collapsing everything into destroy:

```yaml
kind: huram.security-cell.v1
execute: true
operation: create | terminate | recover | destroy

deployment_id: ...
state_locator: ...

components:
  marai:
    ref: <40-char sha>
  atman:
    ref: <40-char sha>
  agni:
    ref: <40-char sha>

placement:
  project: ...
  region: ...
  zone: ...

ingress:
  tenant_registry: <caller-owned policy>

lifecycle:
  backup_mode: archive-only | sealed-recovery
  terminal_backup: required | optional | disabled
  checkpoint_destination: ...
  recovery_authority: ...
```

Semantics:

```text
terminate
  drain -> quiesce -> optional export -> verify -> zeroize -> destroy -> verify absence

recover
  create NEW bootstrap cell -> materialize recovery authority -> import MRS1 -> verify new era

destroy
  destroy exact infrastructure without claiming a successful terminal backup
```

`destroy` is never evidence of a successful `terminate`.

## Terminal artifact model

Huram, not Agni or Marai, chooses durable storage. A sealed-recovery terminal artifact should be immutable and content-addressed or generation-pinned, for example:

```text
security-cell/<deployment_id>/<terminal_export_id>/
  manifest.json
  marai/snapshot.mrs1
  application/...
  hashes.txt
```

The manifest records locators/evidence only:

```text
deployment_id
terminal_export_id
component SHAs
Marai origin era/sequence
snapshot digest
object generation / immutable locator
backup mode
created_at
recovery public-key identity/fingerprint
```

It must not contain ACL passwords, access tokens, plaintext master keys, or the recovery private key.

## Recovery authority

The current MRS1 implementation uses an external X25519 public key for sealed export. The live cell therefore does not require the recovery private key.

Production recovery policy should preserve:

```text
steady-state cell
    has public recovery material only when exporting

ordinary runtime/application identities
    cannot import

explicit Huram recovery operation
    materializes private recovery authority locally
    creates a new Marai authority
    removes recovery material after bootstrap
```

A future external KMS/HSM may protect or derive custody of that recovery private key, but that is a control-plane custody choice rather than a reason to change Marai's Redis/process model.

## Failure semantics

Required terminal backup fails closed:

```text
QUIESCED
    -> export/persist/verify failure
    -> remain failed/quiesced
    -> do not claim authority destruction complete
```

An operator may explicitly abandon recovery and zeroize, but that is a distinct recorded decision.

Unexpected Marai process exit is also a failed/terminal cell event. Do not auto-restart and silently generate an unrelated empty authority behind the same retained identity.

## NQC propagation: only after target-backed qualification

NQC-style distribution is step 16, not part of MRS1 correctness.

The first distributed model is:

```text
one active mutation authority
        |
        | terminal/explicit checkpoint commit
        v
immutable MRS1 object
        +
authoritative checkpoint metadata
        |
        +-- best-effort Logma/NQC hint fanout
        |
        `-- manifest / anti-entropy repair
```

Each standby tracks separate facts:

```text
hinted_checkpoint
confirmed_checkpoint
materialized_checkpoint
```

A Pub/Sub hint cannot make a checkpoint authoritative. Confirmation comes from the authoritative immutable checkpoint metadata/object and its digest/generation.

NQC must not be described as consensus, Redis replication, or active-active KMS. `CREATE`/`ROTATE` remain one-writer authority operations until a separate writer-authority design exists.

## Non-goals

Do not introduce:

- Redis RDB/AOF as Marai durability;
- Redis Cluster/replication as Marai authority continuity;
- automatic Marai restart or automatic MRS1 import;
- recovery private keys in Terraform state or instance metadata;
- tenant policy hardcoded in Agni;
- lifecycle completion inferred from Pub/Sub delivery;
- cleanup by name prefix, label scan, age, or region scan;
- simultaneous independent Marai mutation writers under an NQC label.
