# Security cell lifecycle implementation plan

This plan updates the dormant Atman/Marai security-cell design to fit the current Huram/Smoke/Agni boundaries and the desired lifecycle property:

```text
host/process dies
      ↓
live cryptographic authority dies
      ↓
old encrypted material is unusable by ordinary runtime authority
```

A terminal static backup is allowed, but it is a deliberate lifecycle export and never transparent Marai persistence.

## Phase 0: remove stale policy from Agni

Before adding new functionality, make the existing security-cell templates generic.

Remove from Agni-owned Butane/Ignition defaults:

- hardcoded tenant names such as `logma` and `agni`;
- hardcoded `dashxd` service-account emails;
- hardcoded audiences;
- deployment-specific Atman tenant registries;
- assumptions that every cell runs exactly two Marai tenants;
- restart policies that imply Marai key continuity.

Replace them with caller-supplied generic inputs/artifacts materialized by Huram.

Agni should retain only host-level mechanics and generic unit templates.

## Phase 1: define a durable security-cell request contract in Huram

Huram should own a versioned request shape, conceptually:

```yaml
kind: huram.security-cell.v1
execute: true
operation: create # create | terminate | recover | destroy

deployment_id: ...
state_locator: ...

placement:
  project: ...
  region: us-west1
  zone: us-west1-c

components:
  atman:
    ref: <immutable sha>
  marai:
    ref: <immutable sha>

tenants:
  <tenant>:
    audiences: [...]
    callers: [...]

lifecycle:
  terminal_backup: required # required | optional | disabled
  backup_mode: archive-only # archive-only | sealed-recovery
  backup_destination: <opaque caller-owned destination identity>
  recovery_authority: <required only for sealed-recovery>
```

The request allocates exact deployment/state identity before target mutation. Retries reuse the same identity.

The request must distinguish these operations:

```text
terminate
  quiesce/export/destroy live authority according to policy

recover
  create a NEW authority instance from a sealed recovery artifact

destroy
  destroy exact infrastructure without claiming successful terminal backup
```

`destroy` is not an alias for successful `terminate`.

## Phase 2: formalize the Marai lifecycle contract

Current Marai deliberately has no persistence or restore mechanism. Keep that as the default.

Add an explicit lifecycle API only if sealed recovery is required. It should be local/admin-only, not part of the application Functions API.

Suggested conceptual primitives:

```text
kms_export_sealed(snapshot_id, wrapping_context)
kms_import_sealed(snapshot)
```

or an equivalent host-side administrative tool.

Requirements:

- ordinary `marai-app` cannot export/import authority;
- export is unavailable through Atman's normal HTTP KMS API;
- snapshot contains no plaintext master keys;
- all key versions necessary to decrypt extant envelopes are included;
- key IDs/versions and snapshot metadata are authenticated;
- export is deterministic in manifest structure but cryptographically randomized where sealing requires it;
- import creates a new live authority instance rather than resuming a Redis process image;
- import fails closed on wrong tenant/cell/recovery context;
- snapshot format is explicitly versioned.

Do not implement this by enabling RDB/AOF or serializing the Redis process.

## Phase 3: choose and qualify the recovery sealing boundary

For `sealed-recovery`, use an external recovery authority distinct from normal runtime identity.

The first practical implementation can use Google Cloud KMS envelope wrapping:

```text
Marai live master-key set
        ↓ terminal export
random snapshot DEK
        ↓ encrypt snapshot
sealed snapshot ciphertext
        +
DEK wrapped by recovery KMS key
```

The runtime cell identity must not have `cloudkms.cryptoKeyVersions.useToDecrypt` on the recovery key.

A separate Huram-controlled recovery identity may have narrowly scoped unwrap authority only during an explicit recovery operation.

This preserves:

```text
cell death
  -> no live Marai authority
  -> ordinary runtime cannot decrypt old material

explicit recovery authorization
  -> unwrap sealed snapshot
  -> instantiate NEW Marai authority
  -> old ciphertext becomes usable again only inside that new authority
```

If this distinction is not acceptable for a given cell, select `archive-only` and never export Marai key state.

## Phase 4: terminal backup artifact model

Treat the final backup as a static immutable artifact set, not a mutable remote filesystem.

Recommended layout:

```text
security-cell/<deployment_id>/<terminal_export_id>/
  manifest.json
  application/
    ... static backup payload ...
  marai/
    snapshot.sealed        # sealed-recovery only
    snapshot.meta.json
  hashes.txt
```

The manifest should record only non-secret evidence/locators:

```text
deployment_id
terminal_export_id
cell source/component SHAs
region
backup mode
snapshot format version
artifact hashes
created_at
recovery key resource identity (not secret material)
```

Use immutable object names/generations. A terminal export should commit once, verify, and become read-only.

Do not put runtime ACL passwords, access tokens, plaintext key material, or unwrapped DEKs in the manifest or Terraform state.

## Phase 5: quiesce protocol

The lifecycle needs an explicit quiesce boundary before backup.

Generic sequence:

```text
RUNNING
   ↓
QUIESCING
   ↓
Atman denies/drains new ordinary crypto requests
   ↓
application-specific writers stop or reach a declared checkpoint
   ↓
BACKING_UP
```

Do not assume stopping Atman alone freezes all relevant state if local processes can still access Marai or write application data.

Huram profile composition should describe the components that must acknowledge quiesce for a specific cell. Agni only provides generic hooks/service ordering.

If a cell contains Fatline/Logma workloads, package/profile semantics determine what constitutes a complete application checkpoint.

## Phase 6: terminal export state machine

Use an explicit state machine rather than one shutdown script:

```text
RUNNING
  -> QUIESCING
  -> QUIESCED
  -> EXPORTING
  -> EXPORTED
  -> AUTHORITY_DESTROYED
  -> INFRA_DESTROYED
  -> VERIFIED_ABSENT
  -> COMPLETE
```

Failure states retain enough evidence to know what did and did not happen.

Important rules:

- `EXPORTED` requires durable artifact verification, not merely successful upload exit status;
- Marai remains live until required export has been durably verified;
- once `AUTHORITY_DESTROYED` is reached, the old cell must never return to RUNNING;
- a failed export does not silently proceed to authority destruction when backup is `required`;
- operator-authorized abandonment is a separate recorded transition;
- lifecycle Pub/Sub/callbacks may signal transitions but are not transition authority.

## Phase 7: Atman changes

Keep Atman's normal role narrow:

```text
validated Google identity
  -> tenant route
  -> application Marai capability
```

Add only the lifecycle behavior needed to quiesce ordinary ingress, for example a local administrative drain switch or process stop.

Do not expose terminal export/import through the public tenant API.

The old deployed token-minter path should not be a dependency of the cell lifecycle. Prefer direct WIF/metadata/IAM identity for Huram, Farcaster, and Cloud Function callers.

## Phase 8: Agni host/runtime changes

Agni should provide reusable mechanics such as:

```text
run-scoped tmpfs directories
one Marai process per isolation domain
one Unix socket per Marai process
Atman container/unit template
Marai container/unit template
quiesce/export hook unit templates
backup destination mount/client plumbing
network/egress placement
```

But Agni should not know:

```text
tenant semantic names
caller service-account emails
which backup policy a business workload selected
which KMS recovery key to use
which application state must be checkpointed
```

For Marai, replace `Restart=on-failure` with semantics that fail the cell when Marai exits unexpectedly. Do not automatically regenerate a fresh key set behind the same retained cell identity.

## Phase 9: Smoke qualification package

Add an optional Smoke composition for local lifecycle qualification only if useful.

Minimum archive-only test:

```text
start Marai
create key
encrypt fixture
produce application backup
quiesce
destroy Marai
prove fixture cannot be decrypted anymore
```

Minimum sealed-recovery test:

```text
start Marai A
create key + encrypt fixture
quiesce
export sealed snapshot
verify ordinary app identity cannot unwrap/export
kill Marai A
prove A authority is gone
start Marai B through explicit recovery path
import sealed snapshot
prove fixture decrypts in B
prove B has a distinct live authority/process identity
```

Add negative tests:

```text
wrong recovery key
wrong tenant/cell context
tampered snapshot
tampered manifest
missing key version
unauthorized runtime unwrap
restart without explicit recovery
```

## Phase 10: Huram exact-pair / retained qualification

Huram should qualify exact Atman + Marai + Agni candidates in layers:

```text
Marai component tests
-> Atman component tests
-> Smoke/local lifecycle composition
-> disposable Agni security cell
-> exact terminal export
-> exact authority destruction
-> optional explicit recovery into NEW cell
-> retained/Farcaster-host properties only after local gates
```

Record stable evidence fields:

```text
huram_run_id
deployment_id
terminal_export_id
state_locator
component SHAs
backup mode
backup artifact digest
recovery key resource identity
old cell identity
new recovered cell identity when applicable
```

## Phase 11: Logma/ratelimiter lifecycle integration

Do not make Logma the owner of backup or destruction.

A lifecycle expiry may initiate:

```text
lifecycle.shutdown signal
   ↓
Huram cleanup/termination consumer resolves exact cell
   ↓
quiesce/export state machine
   ↓
exact Terraform/Agni destruction
   ↓
independent absence verification
   ↓
Logma cleanup acknowledgement
```

If terminal export is still pending, Logma registration remains durable/pending. A shutdown signal alone is not proof that keys were backed up or destroyed.

## Phase 12: integration with Cloud Function profiles

The new Cloud Function backend should consume security-cell access only as a resolved capability.

A function profile may compile to:

```text
runtime service account
invoker groups
regional network/egress
Atman audience/endpoint
secret references required to locate the service
```

It should not receive Marai Redis credentials or recovery authority.

This keeps Cloud Functions as ordinary application callers while Huram owns the cell lifecycle.

## First implementation slice

Do not start by implementing sealed recovery.

First prove the core death boundary end to end:

```text
1. genericize Agni security-cell template
2. remove hardcoded tenants/service accounts
3. disable transparent Marai restart semantics
4. create one long-running disposable cell
5. exercise Atman -> Marai application crypto
6. quiesce ingress
7. create a static application backup
8. destroy Marai and exact cell
9. prove old ciphertext is unusable
10. independently verify infrastructure absence
```

That establishes the property we care about without weakening Marai.

Then add sealed recovery as a separately qualified feature:

```text
11. define versioned sealed snapshot format
12. add local/admin-only export/import
13. add external recovery wrapping key
14. prove ordinary runtime cannot unwrap
15. recover into a NEW cell
16. prove old ciphertext only becomes usable after explicit recovery authority is exercised
```

## Non-goals

Do not introduce:

- RDB/AOF for Marai;
- Redis replication/failover for Marai key continuity;
- VM disk snapshots as cryptographic backups;
- automatic Marai restart with silent key regeneration;
- automatic sealed-snapshot restore;
- runtime identities that can unwrap recovery snapshots;
- recovery keys in Terraform state;
- backup success inferred only from an upload exit code;
- tenant policy hardcoded in Agni;
- lifecycle destruction based on labels, age, prefixes, or scans.

The intended model is deliberately asymmetric:

```text
long-running live authority
        ↓
short terminal export window
        ↓
verified immutable backup
        ↓
cryptographic death
        ↓
optional future resurrection only through explicit recovery authority
```
