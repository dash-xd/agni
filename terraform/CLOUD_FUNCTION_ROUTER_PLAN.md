# Cloud Function router implementation plan

This plan implements `CLOUD_FUNCTION_ROUTER_IDIOMS.md` incrementally. The first objective is not a universal serverless framework; it is one small, durable Terraform backend that can deploy already-qualified router source for the existing Go, Python, and Node router families.

## Phase 0: keep existing ownership boundaries

Do not move Huram policy into Agni.

Keep these caller-owned:

- project/account selection;
- WIF/service-account credentials;
- exact repository/ref selection;
- smoke versus retained intent;
- Terraform backend bucket/prefix;
- `deployment_id` / `state_locator`;
- defaultInvoker selection;
- dedicated function invoker selection;
- invokergroup membership;
- Fatline/Logma/ratelimiter semantic profile composition;
- lifecycle registration and cleanup acknowledgement.

Agni owns generic GCP implementation only.

## Phase 1: generic Gen2 HTTP function module

Create:

```text
terraform/cloud-function/
  README.md
  versions.tf
  variables.tf
  locals.tf
  source.tf
  function_gen2.tf
  iam.tf
  outputs.tf
```

First implementation target: `google_cloudfunctions2_function` HTTP functions.

Inputs:

```text
project
region
function_name
runtime
entry_point
source_dir
runtime_service_account_email
invoker_members
allow_unauthenticated
min_instance_count
max_instance_count
available_memory
timeout_seconds
ingress_settings
environment_variables
labels
```

Source resources:

```text
archive_file
-> google_storage_bucket (one per function, same region)
-> google_storage_bucket_object source/<sha256>.zip
-> google_cloudfunctions2_function
```

Bucket requirements:

```text
location = region
uniform_bucket_level_access = true
public_access_prevention = "enforced"
force_destroy = false by default
```

Use deterministic globally unique bucket naming from project/function/region identity plus a short hash. The bucket name must not depend on source digest.

For Gen2 invocation, materialize `roles/run.invoker` against the underlying Cloud Run service. Keep unauthenticated access separate from authenticated member sets.

Outputs must include canonical function identity, function URI, source bucket/object/generation/digest, runtime SA, and invoker members.

### First qualification target

Use `dash-xd/gospace-minimal` because it already has a qualified Gen2 Functions Framework contract.

The adapter/preparation step must preserve its root `function.go` re-export and internal implementation layout.

Prove:

```text
fresh create
authorized invoke
unauthorized denial
source-only update on same state
same source bucket after update
exact destroy
```

## Phase 2: request compiler / typed Go surface

Add an ordinary Go package in Agni, for example:

```text
cloudfunction/
```

Keep it thin. It should validate and materialize Terraform input files/arguments; it must not replace Terraform semantics.

Suggested public types:

```go
type Generation int

type FunctionSpec struct {
    ID                     string
    Project                string
    Region                 string
    Generation             Generation
    Adapter                string
    Runtime                string
    EntryPoint             string
    SourceDir              string
    RuntimeServiceAccount  string
    DefaultInvoker         string
    InvokerMembers         []string
    InvokerGroups          []string
    Environment            map[string]string
    Labels                 map[string]string
}

type InvokerGroup struct {
    Name    string
    Members []string
}
```

The compiler resolves:

```text
singular function invoker
  else defaultInvoker
  + referenced invokergroups
  -> deduplicated IAM member set
```

Do not put Fatline/Logma/ratelimiter names in this package.

## Phase 3: invoker identity compiler

Add deterministic validation for IAM member strings and group expansion.

Recommended rules:

- `defaultInvoker` is optional generic input;
- a function-specific singular invoker replaces `defaultInvoker` as the singular fallback;
- referenced invokergroups add members;
- duplicate members collapse;
- empty resolved member set is valid only when explicitly requested as no authenticated invoker;
- `allUsers` is permitted only when `allow_unauthenticated` is explicitly true;
- runtime service account is never implicitly granted invocation merely because it executes the function.

Do not create a Google Group for each invokergroup. Treat groups as control-plane sets that compile to ordinary IAM members.

A later extension may support generated dedicated service accounts, but the first slice should prefer caller-provided SAs so identity lifecycle remains explicit.

## Phase 4: Node adapter

Add a small deployment fixture/adapter for `dash-xd/simple-router-builder`.

Preserve its actual dependency model:

```text
router
finalhandler
```

Do not add Express/Hono as deployment dependencies.

The prepared source tree should contain:

```text
package.json
index.js / function entry module
router source
```

with an exported HTTP handler compatible with the selected Node Functions Framework runtime.

Qualify it through the same generic Gen2 module used by gospace-minimal. This is the important proof that Agni owns cloud deployment while the router repository owns language/runtime code.

## Phase 5: Gen1 function submodule

Add Gen1 support as a separate Terraform implementation behind the same caller-facing conceptual schema.

Files:

```text
function_gen1.tf
iam_gen1.tf
```

First target: `dash-xd/pyspace-minimal` Python 3.12.

Preserve:

```text
main.py
requirements.txt
cloud_function_app
ROUTER_MODULE
entry point main
```

Use Gen1 invocation IAM rather than pretending Gen1 and Gen2 share the same IAM target.

A retained migration from generation 1 to generation 2 requires a new infrastructure/ownership operation; do not represent it as an in-place runtime update.

## Phase 6: gospace.cloud composition adapter

Treat `xd-dash/gospace.cloud` as an exact composition producer, not as another Terraform implementation.

Flow:

```text
exact gospace.cloud manifest/ref
-> materialize pinned pyspace + gospace pair
-> build Linux/amd64 gospace binary
-> place binary into qualified pyspace source tree
-> deterministic archive
-> generic Gen1 function module
```

The existing private-by-default behavior remains.

Agni should not reinterpret the Android `repo` manifest or make mutable branch selections inside Terraform.

## Phase 7: Huram pseudo-dispatch integration

Add a Huram request schema only after the Agni module is independently qualified.

Suggested conceptual request:

```yaml
kind: huram.gcp-http-function.v1
execute: true
operation: create # or update/destroy

deployment_id: ...
state_locator: ...

source:
  repository: dash-xd/gospace-minimal
  ref: <immutable sha>
  adapter: gospace-minimal

function:
  name: ...
  project: ...
  region: us-west1
  generation: 2

identity:
  runtime_service_account: ...
  invoker: ...
  invokergroups:
    - farcaster

profiles:
  - <caller-owned semantic profile refs>
```

`profiles` are compiled by Huram before Agni/Terraform. Agni receives provider facts, not semantic package names.

### Create

The pseudo-dispatch controller allocates and commits exact deployment/state identity before target mutation. Retry of the same request reuses that identity.

### Update

The request names the exact retained `deployment_id` and `state_locator`. Terraform attaches that state and reconciles the same function.

### Destroy

The request names the exact deployment/state identity. Destruction is followed by independent absence verification before any Logma lifecycle cleanup acknowledgement.

## Phase 8: profile compiler integration

Formalize a Huram-side compiler:

```text
Fatline package requirements
+ Logma requirements
+ ratelimiter requirements
        |
        v
resolved function cloud profile
```

The resolved result should contain only cloud/provider facts such as:

```text
invoker group names / principal members
runtime service account
secret references
environment variables
VPC/subnet/egress requirements
lifecycle metadata
labels/evidence fields
```

This keeps package semantics where they already belong while allowing Cloud Functions to participate in the same profile vocabulary as Farcaster/Fatline workloads.

Do not duplicate Redis ACL/profile internals in Agni.

## Phase 9: regional network integration

After basic authenticated HTTP invocation is qualified, add optional networking inputs for the Farcaster regional topology.

Gen2 should support the Cloud Run functions networking model independently from Gen1 connector semantics.

Keep this optional:

```text
no VPC config
or
resolved regional network/subnet/egress config
```

The region remains one of the strongest identities in the request. Source bucket, function, and regional network choice must agree or fail closed.

This is where Huram can bind a function to a Fatline/Farcaster profile that requires private regional egress without forcing every simple router to inherit that topology.

## Phase 10: lifecycle handoff

Once a function is deployed and qualified, Huram may register its exact deployment with Logma/ratelimiter lifecycle using the existing create-once lifecycle contract.

Persist at least:

```text
deployment_id
state_locator
project
region
function_name
source digest
policy code / lifecycle policy
shutdown route
```

Shutdown remains a signal. The cleanup consumer must resolve the exact Terraform state, destroy only that state-owned deployment, independently verify absence, then acknowledge cleanup.

## Proposed test matrix

### Generic Terraform

```text
same-region bucket validation
private bucket validation
content-addressed source object
stable bucket across source update
runtime SA attachment
Gen2 roles/run.invoker materialization
no allUsers by default
outputs contain exact identities
```

### Invokergroups

```text
defaultInvoker only
function-specific invoker only
defaultInvoker overridden by specific invoker
one group
multiple groups
duplicate members collapse
invalid group reference fails
unauthenticated requires explicit opt-in
```

### State semantics

```text
create against fresh backend prefix
retry same create request uses same identity
update against exact retained prefix
missing retained state fails closed rather than silently creating sibling
exact destroy
```

### Runtime adapters

```text
gospace-minimal Gen2
simple-router-builder Node Gen2
pyspace-minimal Gen1
gospace.cloud exact Gen1 composition
```

## What not to build yet

Do not initially add:

- a custom Terraform provider;
- a Terraform replacement DSL;
- automatic repository cloning inside Terraform;
- automatic import-by-name as normal update behavior;
- one GCS state bucket per function;
- Google Groups as the implementation of invokergroups;
- profile-specific conditionals in Agni;
- cross-region source buckets;
- public invocation by default;
- cleanup by labels/prefix/age;
- automatic Gen1 -> Gen2 retained migration;
- a large universal serverless framework.

The useful first product is intentionally small:

```text
qualified source tree
-> Agni generic module
-> private regional source bucket
-> authenticated function
-> exact state identity
```

Everything else composes above or beside that boundary.