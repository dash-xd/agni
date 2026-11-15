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
