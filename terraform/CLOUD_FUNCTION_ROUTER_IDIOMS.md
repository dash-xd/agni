# Agni Cloud Function router deployment idioms

This document defines the generic Agni boundary for deploying small HTTP routers to Google Cloud Functions / Cloud Run functions. It is intentionally provider/runtime focused. Organization-specific project IDs, credentials, repositories, promotion policy, exact source selection, lifecycle policy, Fatline scope, Logma registration, and ratelimiter policy remain caller-owned inputs, normally materialized by Huram.

The design follows `AGNI_IDIOMS.md`: Terraform remains authoritative for Terraform state, providers, plan/apply, and resource identity. Agni exposes reusable implementation; it does not invent a competing infrastructure language.

## 1. Goal

Make the common operation:

```text
exact router source
+ runtime adapter
+ GCP project/region
+ runtime identity
+ invocation identity
+ resolved capability/profile inputs
        |
        v
regional private source artifact
        |
        v
Cloud Function
        |
        v
qualified HTTP boundary
```

small enough that Go, Python, and Node router repositories do not each need to own bespoke GCP provisioning logic.

The first supported router families are:

```text
Go
  dash-xd/gospace-minimal

Python
  dash-xd/pyspace-minimal
  xd-dash/pyspace

Pinned Python + Go/WASM composition
  xd-dash/gospace.cloud

Node
  dash-xd/simple-router-builder
```

The runtime family is an explicit adapter choice, not an inferred language abstraction. Each adapter owns the packaging/buildpack details needed by that runtime.

## 2. Responsibility boundary

```text
Huram / caller
  exact immutable source refs
  POST-vs-PUT lifecycle intent
  project/account/region policy
  WIF / target credentials
  retained state locator
  defaultInvoker choice
  dedicated invoker choice
  invokergroup membership
  Fatline / Logma / ratelimiter profile composition
  qualification and retained evidence
        |
        v
Agni
  generic router deployment spec
  deterministic source packaging contract
  per-function regional source bucket
  Cloud Function resources
  runtime service-account attachment
  resolved invoker IAM materialization
  Terraform outputs
        |
        v
Google Cloud
```

Agni MUST NOT embed xd-dash/dash-xd repository names, production project IDs, profile names, credentials, or organization deployment policy in Terraform defaults.

Profile semantics remain outside Agni. Agni accepts the resolved cloud-facing result of a profile: IAM principals, runtime service-account identity, environment values, secret references, networking inputs, and labels/metadata where applicable.

## 3. Function identity is distinct from deployment operation

A function has an explicit stable resource identity:

```text
function_id
project
region
generation
state_locator
```

A deployment operation has request identity:

```text
request_id
source_sha
source_digest
composition_id
```

Do not derive Terraform ownership from mutable source paths or names alone.

### Create / POST semantic

Create means allocate a new function/deployment identity and a new exact state lineage, then apply the module against that lineage.

```text
POST-like request
  -> allocate deployment_id/function_id
  -> allocate exact state_locator
  -> package exact source
  -> terraform init against new state
  -> create
```

Repeated execution of the same create request MUST be idempotent against the same allocated identity; it must not allocate another identity merely because a workflow retried.

### Update / PUT semantic

Update means reuse the exact retained function identity and state locator.

```text
PUT-like request
  -> resolve existing deployment_id/function_id
  -> attach exact state_locator
  -> package exact successor source
  -> terraform init against retained state
  -> plan/apply
```

Deleting Terraform state is not an implementation of POST. Import/discovery is repair/recovery, not the normal update path.

This matches Huram's existing distinction between disposable smoke and retained slots.

## 4. Per-function source bucket

Each function owns a dedicated Cloud Storage staging bucket by default.

Required properties:

```text
bucket location == function region
uniform bucket-level access == true
public access prevention == enforced
one bucket owner == one function identity
```

The bucket name is derived deterministically from caller-safe identity plus a bounded hash because GCS bucket names are globally unique. The exact naming grammar is implementation detail, but changing router source MUST NOT rename the bucket.

Example conceptual identity:

```text
agni-gcf-<project-number>-<region>-<function-hash>
```

Source objects are immutable/content-addressed:

```text
source/<sha256>.zip
```

The Cloud Function `storage_source` references the exact object and, where practical, exact object generation. Never use a mutable `function.zip` object as the only source identity.

The bucket is staging infrastructure, not application storage. Static/browser assets that intentionally live outside the function follow the separate retained static-asset idiom and should not be mixed into the source bucket contract.

Google may copy the submitted archive into its own managed regional source bucket; the Agni bucket remains the Terraform-owned source staging boundary.

## 5. Packaging contract

Terraform should consume an already prepared source tree or archive contract; the language adapter determines what must appear in that tree.

Prefer this split:

```text
router adapter / preparation
  -> deterministic source directory
  -> archive_file
  -> sha256-addressed GCS object
  -> google_cloudfunctions*_function
```

The archive digest is an output and evidence field.

Do not make the Terraform module clone Git repositories or perform network-dependent package composition. Exact source selection/composition belongs before Terraform target mutation.

### Go adapter: gospace-minimal

Preserve the repository's Functions Framework/buildpack contract:

```text
root function.go re-export
internal/function implementation
GOOGLE_FUNCTION_SOURCE=internal/function when required by selected deployment path
entry point Main
```

The root re-export is semantically significant because the generated buildpack wrapper type-asserts the bare HTTP function signature.

### Python adapter: pyspace-minimal

Preserve the Gen1 Python 3.12 host contract initially:

```text
main.py
requirements.txt
cloud_function_app package
ROUTER_MODULE=<router module>
entry point main
```

A router is composition input; Terraform does not need to understand Python route registration.

### Python + Go/WASM adapter: gospace.cloud

Treat the pinned composition as one qualified source artifact:

```text
pyspace host
+ pinned gospace executable
+ deployment environment
```

Agni packages/materializes the already-qualified composition; it does not replace the manifest/pinning model.

### Node adapter: simple-router-builder

Use the repository's actual light dependency surface (`router` + `finalhandler`) and an explicit Functions Framework entry module. Do not introduce Express/Hono merely for deployment unless the router itself chooses that dependency.

The adapter should emit a source tree with an exported HTTP handler compatible with the chosen Node Cloud Functions runtime.

## 6. Generation is adapter metadata

Do not force all adapters onto Gen2 in the first slice.

Initial mapping:

```text
gospace-minimal       -> Gen2
pyspace-minimal       -> Gen1
pyspace/gospace.cloud -> Gen1 until separately qualified otherwise
simple-router-builder -> Gen2 preferred
```

The generic spec carries `generation = 1 | 2`. Adapter defaults may choose a generation, but the Terraform implementation keeps Gen1 and Gen2 provider resources behind separate internal modules/resources because their source, IAM, and runtime semantics differ.

Migration of a retained function from Gen1 to Gen2 is an infrastructure/ownership change, not an ordinary runtime PUT.

## 7. Runtime service account and invoker identity are different

Never conflate:

```text
runtime service account
  identity used by the function while executing

invoker principal
  identity allowed to call the HTTP function
```

Both are explicit inputs/outputs.

### Runtime identity

A function accepts either:

```text
runtime_service_account_email = <caller-provided SA>
```

or an explicit request for Agni to create a dedicated runtime service account if/when that capability is implemented.

Do not silently fall back to a broad default compute service account in retained deployments.

### Invoker identity

A function resolves invocation access in this order:

```text
function-specific singular invoker
  else caller-supplied defaultInvoker
  plus explicitly referenced invokergroups
```

`defaultInvoker` is a deployment-policy value and therefore caller-owned. Agni only receives the resolved principal.

For Gen2, invocation materializes against the underlying Cloud Run service with `roles/run.invoker`. For Gen1, invocation uses the Gen1 Cloud Functions invocation role.

Unauthenticated invocation is an explicit separate boolean/capability and defaults false.

## 8. Invokergroups are logical sets, not a new Google identity primitive

An `invokergroup` is a named control-plane grouping that compiles to a set of IAM members.

Conceptual input:

```hcl
invoker_groups = {
  farcaster = [
    "serviceAccount:farcaster-gateway@...",
    "serviceAccount:farcaster-world@...",
  ]

  operators = [
    "serviceAccount:operator@...",
  ]
}
```

A function references group names:

```hcl
function_invoker_groups = ["farcaster"]
```

Agni receives or can accept this generic map/set form and flattens it deterministically into IAM bindings. The group is not required to be a Google Group and does not imply shared service-account credentials.

This keeps membership composable with WIF/service-account impersonation and avoids creating another credential-sharing abstraction.

## 9. Profiles compile above Agni

Fatline, Logma, and ratelimiter profiles are semantic capability declarations. Their package/profile layer owns what authority is required.

The compilation path is:

```text
package semantic requirements
        |
        v
Fatline/profile composition
        |
        v
Huram provider compiler
        |
        +-- invoker principals/groups
        +-- runtime service account
        +-- env/secret refs
        +-- VPC/egress requirements
        +-- lifecycle registration inputs
        |
        v
Agni generic Terraform inputs
```

Do not put `profile = "logma"` branches inside generic Agni Terraform.

A future generic Agni Go type may carry an opaque resolved profile result, but it must contain provider-level facts rather than package-specific semantic names.

## 10. Suggested generic deployment schema

Conceptually:

```go
type FunctionSpec struct {
    ID         string
    Project    string
    Region     string
    Generation int

    Adapter string
    Runtime string
    EntryPoint string
    SourceDir string

    RuntimeServiceAccount string
    DefaultInvoker string
    InvokerGroups []string

    Environment map[string]string
    Labels map[string]string

    MinInstances int
    MaxInstances int
    Memory string
    TimeoutSeconds int
    Ingress string
}
```

Terraform should receive equivalent primitive values/maps/sets. This Go type is not a replacement DSL for Terraform; it is a convenient typed request/compiler surface that eventually emits ordinary Terraform inputs.

Keep source identity/evidence separate:

```go
type SourceEvidence struct {
    SourceSHA string
    ArchiveSHA256 string
    CompositionID string
}
```

## 11. Terraform module layout

Prefer a new isolated module tree rather than adding Cloud Function resources to the existing CoreOS member root module:

```text
terraform/
  cloud-function/
    README.md
    variables.tf
    locals.tf
    source.tf
    function_gen1.tf
    function_gen2.tf
    iam.tf
    outputs.tf

  cloud-function-router/
    README.md
    variables.tf
    adapter_go.tf
    adapter_python.tf
    adapter_node.tf
```

The first module owns the generic cloud resource. The second can remain very thin and only encode adapter defaults/validation. If adapter logic is better expressed entirely before Terraform, omit `cloud-function-router/` and keep one generic module.

Do not mix this into `terraform/main.tf`, which currently owns the CoreOS/Farcaster-style member topology and remote leader state.

## 12. State/backends

Agni must not pick organization-specific backend bucket names.

Callers provide backend configuration. Huram should preserve exact state identity:

```text
state bucket
+ state prefix / locator
+ project
+ region
+ function_id
```

Recommended retained prefix shape is caller policy, for example:

```text
cloud-functions/<region>/<function-id>
```

A disposable create request receives a new exact prefix. A retained update reuses it.

Source buckets are per function. Terraform state buckets SHOULD be shared/control-plane resources rather than one state bucket per function unless isolation policy requires otherwise.

## 13. Lifecycle integration

A deployed function may participate in Logma/ratelimiter lifecycle, but Pub/Sub/callback signaling is not Terraform ownership.

Required destructive chain remains:

```text
lifecycle shutdown signal
  -> cleanup consumer resolves exact deployment_id + state_locator
  -> terraform destroy against exact state
  -> independent absence verification
  -> lifecycle cleanup acknowledgement
```

Never destroy by name prefix, region scan, label scan, age, or profile membership.

## 14. Qualification

Follow Huram local-before-target authority.

Generic sequence:

```text
exact immutable router/runtime refs
-> adapter-specific local tests/build
-> deterministic package
-> hash source archive
-> terraform fmt/validate
-> acquire target-mutating GCP authority
-> attach exact state lineage
-> terraform plan/apply
-> read back function/source bucket/IAM identity
-> invoke canonical boundary with authorized invoker
-> prove unauthorized invocation is denied
-> record exact evidence
```

For disposable smoke:

```text
create isolated identity
-> qualify
-> exact destroy or explicit retain handoff
```

For retained update:

```text
reuse exact state/function identity
-> mutate only required layer
-> verify retained ownership did not drift
```

## 15. Outputs are part of the control-plane contract

At minimum expose:

```text
function_id
function_name
project
region
generation
canonical_function_uri
underlying_run_service_uri when Gen2
source_bucket
source_object
source_generation
source_archive_sha256
runtime_service_account
resolved_invoker_members
```

Huram can persist these as evidence/locators without scraping provider naming conventions.

## 16. First-slice invariants

The initial implementation should prove these before adding profile automation:

1. one exact router source produces one content-addressed archive;
2. source bucket is private and exactly regional;
3. bucket identity is stable across runtime source updates;
4. create uses a fresh exact Terraform state lineage;
5. retained update reuses the same lineage;
6. runtime SA and invoker SA are independent;
7. defaultInvoker works when no function-specific invoker is supplied;
8. a singular function-specific invoker overrides defaultInvoker;
9. invokergroup membership adds principals deterministically;
10. unauthorized invocation is denied;
11. Gen2 uses Cloud Run invocation IAM;
12. exact destroy uses state/deployment identity and removes only owned resources.

Only after this generic boundary is qualified should Huram compile Fatline/Logma/ratelimiter profiles into the invoker/runtime/network inputs.