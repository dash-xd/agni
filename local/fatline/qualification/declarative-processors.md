# Declarative subscription processor units: render-only qualification

This candidate extends the existing Agni-owned CoreOS rootless Quadlet renderer.
It does not modify, install, enable, or restart any of VM1's existing service units.

## Boundaries

- Agni renders service identities, dependency edges, credential mount paths, and restart policy.
- Skymill owns consumer-group processing and Redis PEL recovery.
- Probot owns the subscription-scoped execution fence and handler semantics.
- nix.xd owns only the generic Nix-Alpine transport and Nix execution interface.

The candidate emits four rootless Quadlet source files:
- `fatline-arm-vm1-subscription-a-skymill.container`
- `fatline-arm-vm1-subscription-a-processor.container`
- `fatline-arm-vm1-subscription-b-skymill.container`
- `fatline-arm-vm1-subscription-b-processor.container`

Each Skymill candidate requires Redis and the Nginx proxy. Its Probot processor requires
the corresponding Skymill candidate and Redis. Logma is a soft dependency; lost hints
cannot be allowed to suppress stream polling. The two subscriptions have independent
credential mount directories and service names.

## Fail-closed qualification boundary

The output is deliberately inert. It has no `[Install]` sections, includes a
missing activation guard, and runs Probot with
`PROBOT_RUNTIME_WORKER_ENABLED=false`. No credentials are rendered.

The source-pinned SubscriptionExecutionStore has passed the isolated live fixture, but
the ordinary Probot runtime factory has not yet been updated to use that
subscription-scoped store. Starting worker-enabled router services using these
unit templates would therefore violate the separately qualified delivery fence.

The current gate checks **rendering and static lifecycle policy only**.
It does **not** claim that the Podman systemd generator has accepted the Quadlets,
nor that systemd has started or independently restarted them.

## Next qualification, after this one passes

1. Integrate and qualify subscription-mode factory wiring, binding the execution
   namespace to the exact Skymill consumer-group identity.
2. Replace the inert candidate with pinned source-derived executable paths,
   complete scoped environment variables, and read-only credential file contracts.
3. Run the real Podman systemd generator in CoreOS dry-run mode with the rendered units.
4. Run each candidate as a disposable, isolated systemd user service generation,
   exercise independent stop/restart and Redis PEL reclaim, and verify the five
   baseline VM1 service InvocationIDs remain unchanged.
5. Only consider production activation after external effect/reconciliation gates.

## Run

```sh
make -C local/fatline deployment-qualify-declarative-processors \
  DEPLOYMENT=vm1 NIX_XD_DIR="$HOME/workspace/nix.xd20261112" \
  PROVIDER=podman MACHINE=coreos-arm64
```

Expected marker:
`AGNI_DECLARATIVE_PROCESSORS_CONTRACT=passed roles=4 subscriptions=2 unit_format=quadlet activation=blocked worker=disabled`
