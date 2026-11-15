# Probot subscription-scoped factory candidate

This gate follows the qualified CoreOS Podman generator dry-run but does not
alter or activate VM1. Probot candidate source is pinned by
`qualification/probot-factory-ghxd-sources.json` and seeded by Smoke GHXD
into `/workspaces/probot-runtime20261116`.

The Nix-Alpine app `#subscription-factory-contract` validates the exact
revision, parses the three changed runtime files and runs Node's built-in tests
for subscription execution, factory selection, and the regular
`createGitHubAppRuntime` construction path. Tests use a deterministic
in-memory boundary; no Redis server, GitHub API, or live Skymill is contacted.

The shared `RedisStore` remains responsible for app registration, webhook
ingress and delivery correlation. The runtime worker and its
`reconcileAmbiguousDelivery` operation use a subscription-scoped
`SubscriptionExecutionStore`. The legacy no-subscription path remains the
same shared store.

The subscription candidate requires explicit
`PROBOT_RUNTIME_SUBSCRIPTION_APPLICATION_ID`,
`PROBOT_RUNTIME_SUBSCRIPTION_ID`, `SKYMILL_URL`,
`SKYMILL_CONSUMER_GROUP` and `SKYMILL_CONSUMER` for normal startup.
All four execution identities (org, tenant, application, subscription) are
validated. The Redis prefix remains shared for ingress, while the execution
namespace varies by all four identities.

The factory test does **not** qualify Redis persistence, live worker execution,
independent systemd restart, externally applied GitHub effects, or production
activation. Those require later Agni-controlled isolated runtime gates.

## Isolated normal-factory live qualification

`deployment-qualify-factory-live` stages the exact factory source as a rooted,
immutable Nix artifact and invokes the existing isolated CoreOS VM1 guest
qualification. It starts disposable Redis and two independently authenticated
Skymill HTTP peers, then constructs two execution workers using the source's
actual `createGitHubAppRuntime()` factory. The existing isolated signed-webhook
ingress seeds the shared source delivery, while each factory selects its own
Skymill group and durable subscription execution namespace.

The gate tests group-A completion while group B has a pending entry, SIGKILL of
Skymill peer B, factory-B teardown/reconstruction while factory A stays
connected, pending-entry reclaim by the restarted peer, and duplicate-delivery
replay without duplicate effects in either scope. It preserves VM1's existing
five systemd unit invocation identities and performs candidate cleanup.

This is a **factory recreation and Skymill-peer crash gate**, not proof of
independent Probot operating-system process restart, Redis crash durability,
or production systemd lifecycle. The Probot process-kill and Quadlet lifecycle
gates remain separate. No production service or network is activated.
