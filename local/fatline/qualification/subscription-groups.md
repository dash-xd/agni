# Probot subscription-group qualification

This is an **additive isolated candidate**, not a production activation.

## Ownership

- Probot owns application registry, ingress delivery metadata, and subscription-specific execution fences.
- Skymill owns Redis Streams consumer groups, pending delivery recovery, ACK/NACK, and transport authorization.
- Agni selects pinned sources, composes the live candidate, and records pass/fail evidence.
- Smoke GHXD owns authenticated read-only Git source synchronization.
- Nix-Alpine / CoreOS provide reproducible host and guest execution without changing VM1's existing service invocation IDs.

## Execution identity

For the new explicit subscription mode, Probot uses the logical tuple
`(orgId, tenantId, applicationId, subscriptionId, githubDeliveryGuid)`.
The first four fields derive the Redis execution namespace via SHA-256 of an ordered JSON tuple.
The GitHub GUID remains the delivery key inside that namespace.

The GitHub application registry and original ingress delivery record remain shared.
Each authorized subscription has independent execution, settlement and reconciliation records.
This avoids weakening the previously qualified single-subscription delivery fence.

Subscription identity is pinned to the actual Skymill consumer-group string in the live candidate;
two processors within **one** group use one subscription ID and share a fence.

## Live qualification

1. Launch isolated Redis and two independent Skymill HTTP service instances, with distinct groups and distinct bearer tokens. Verify cross-group bearer tokens are rejected with HTTP 401.
2. Ingest one signed webhook into the shared stream.
3. Let group B receive it, creating one pending entry; terminate B's Skymill service.
4. Allow group A to execute and ACK. B's effect must remain absent.
5. Restart group B under a new consumer identity. Verify Redis PEL recovery, increased delivery attempt, and one successful effect.
6. Publish a second stream record with the same GitHub delivery GUID but a distinct transport idempotency key.
7. Both groups must independently ACK without re-executing their successful effects.
8. Always clean up the isolated candidate and verify original VM1 systemd service invocation IDs remain unchanged.

Passing proves one effect **per subscription** for this fixture, not globally exactly once.
It does not prove GitHub API idempotency, ambiguous external side-effect reconciliation, or independent authorization policy for arbitrary future subscriptions.

## Source selection

Smoke GHXD enforces `<repository>YYYYMMDD` checkout names. The new isolated source uses
`probot-runtime20261115`, a reserved next-generation checkout, to avoid moving the
already qualified `probot-runtime20261114` alias. Both remain exact-SHA pinned.
The separate subscription artifact is named `probot-subscription20261114`.

## Execution

```sh
make -C local/fatline check-deployment
make -C local/fatline deployment-seed-subscription-source DEPLOYMENT=vm1 NIX_XD_DIR="$HOME/workspace/nix.xd20261112" PROVIDER=podman MACHINE=coreos-arm64
make -C local/fatline deployment-qualify-subscription-contract DEPLOYMENT=vm1 NIX_XD_DIR="$HOME/workspace/nix.xd20261112" PROVIDER=podman MACHINE=coreos-arm64
make -C local/fatline deployment-qualify-subscription-groups DEPLOYMENT=vm1 NIX_XD_DIR="$HOME/workspace/nix.xd20261112" PROVIDER=podman MACHINE=coreos-arm64
```
