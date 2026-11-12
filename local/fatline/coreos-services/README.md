# CoreOS application services, first VM

Agni composes pinned Logma API and Skymill HTTP binaries for both supported Linux
architectures. nix.xd selects the architecture and runtime. The services consume
closures from the authoritative owner's store over the existing read-only 9P
mount, using separate rootless containers and systemd units. Neither upstream
all-in-one images nor architecture-specific service orchestration is used.

This package extends the already prepared host-link scope. Its existing publisher
and subscriber ACL identities are preserved. Agni's tracked production policy is
rendered for that scope, with independent Logma, Skymill and bootstrap passwords.
Only hashes enter Redis's ACL file. Credentials are generated at runtime outside
Nix builds and mounted into only the corresponding process. Logma's small shell
adapter reads its credential files because its pinned API expects environment
variables; Skymill accepts its credential file directly.

Activation explicitly restarts the existing ephemeral Redis/nginx pair once to
install the expanded ACL. That discards prior in-memory Redis fixture state. It
then installs pinned Ratelimiter lifecycle Functions using the bootstrap identity,
revokes that identity, installs the application Quadlets and starts the services.
Application HTTP ports stay unpublished on the internal Fatline network; Skymill's
pinned HTTP adapter has no application authenticator, so public HTTP exposure is
outside this contract. Redis TCP ingress remains guest loopback nginx -> Unix
socket. The host Smoke subscriber stays on its previously qualified Wisp route.

The services have separate credential mounts. Only Logma mounts its writable
lifecycle state directory. Shared store/socket mounts are read-only in readers;
Redis alone owns its socket output and writable memory state. Guest rootless owner
and administrators remain trusted; label=disable follows the qualified 9P model
and is not a claim of SELinux confinement between these services.

Qualification checks strict Logma lifecycle readiness; a Skymill publish,
idempotency, receive and ack round trip; scoped Redis command/key denials; actual
read-only mounts; private credential permissions and unpublished HTTP ports.
Full Logma resource/lifecycle semantics, production HTTP authentication, crash
recovery, durable Redis persistence, and multi-VM application behavior remain
separate gates. An interrupted activation keeps its roots and requires explicit
stop/retry or sandbox reset. It is not automatically promoted to a successful run.


## Probot webhook VM1 candidate (new revisions)

The existing `coreos-services-vm1` activation is a qualified earlier
two-service profile; its pinned artifacts and Redis ACLs must not be
silently replaced with the newer webhook integration binaries.

Run Agni's `#qualify-integration --scenario probot-webhook --phase guest-plan`
to build/reuse the three exact ARM64 artifacts and produce the credential-free
`~/.local/state/agni/probot-webhook/guest-plan-vm1.json` in the authoritative
Nix-Alpine owner. The planner validates the exact Nix store paths, the
Probot router and Node entrypoint, source SHAs, distinct role credentials,
private network and read-only store mounts, then emits three *candidate*
systemd user-Quadlet descriptions. Its tests reject mismatched revisions
and any attempt to include a GHXD OAuth credential as application authority.

**The plan is not an activation.** The guest still requires:

- Revised Skymill Redis ACL grants for the pinned implementation's
  `skymill:{binding-hash}:stream:...`, idempotency and correlation keys.
  The older `{scope}:skymill:...` ACL does not authorize these keys.
  Validate the exact Binding hash using the pinned Skymill keyspace code.
- New, distinct Probot state and lifecycle-publication Redis identities,
  plus a subscription-only observer principal. Logma itself retains its\n  separate `logma` principal. Preserve the current host-link
  publisher/subscriber identities. Redis is RAM-only; its in-memory ledger
  does not survive Redis restart.
- Process-scoped encrypted runtime delivery of the Huram App private key,
  webhook secret, operator credential and matching installation/binding
  evidence. These **must never** be read from the GHXD user OAuth token,
  embedded in the Nix store, or introduced into a systemd unit's literal
  environment.
- Guest-side activation via Agni's existing `guest.sh` and lifecycle
  locking, using runtime-bound configuration and credential mounts. Runtime
  readiness needs actual Logma and Skymill HTTP/Redis probes, not only an
  active systemd unit.
- A real externally delivered GitHub webhook, a matching Skymill durable
  provider delivery ID and ACK/NACK settlement, plus independent Logmash
  and serverless SSE hint observations.

The candidate includes no HTTP port publications. It intentionally does
not install units, rotate ACLs or invoke the actual webhook. A passing
guest-plan establishes artifact identity and composition shape, **not**
CoreOS VM1 readiness or live integration success.

## Scoped Redis ACL policy candidate

Agni's `--scenario probot-webhook --phase acl-plan` derives a non-secret
Redis ACL policy from the pinned webhook source manifest and the tracked
baseline policy. It preserves the original Logma, Skymill and bootstrap
identities, adds Probot state and independent lifecycle publish/subscribe
principals, and scopes Skymill to its exact 32-hex Binding hash slot.
The existing ACL renderer now supports additional principals and canonical
Redis hash-slot notation without changing old policy output order.

The `acl-plan` candidate is written under the Nix-Alpine writer's
`~/.local/state/agni/probot-webhook/redis-policy-vm1.json` and does not
create credentials or modify the active Redis ACL. The Probot state prefix,
service environment, command grants, and source-derived Binding must be
qualified against actual applications before the policy is applied. No
success marker from `acl-plan` authorizes guest activation or webhook delivery.

## Disposable Redis ACL enforcement

The `--phase acl-runtime` gate derives the pinned six-principal policy,
generates ephemeral credentials outside the Nix store, and uses Agni's
existing ACL renderer to load them in a disposable Unix-socket-only Redis
process inside the authoritative Nix-Alpine writer. It checks positive
key, channel and authentication operations plus Redis NOPERM responses for
cross-scope keys/channels, ACL and CONFIG administration, and
publication by subscription-only identities. It does not rewrite a guest
ACL or launch any CoreOS application. Temporary credentials and Redis
data are removed at exit.

The `probot_state` prefix is aligned to the Probot runtime
`org_id=xd-dash` and `tenant_id=probot-test` convention; the guest
activation must explicitly bind those same identities and the appropriate
Redis DB. The policy is only a candidate until actual Probot and Skymill
behavior has been exercised. Redis is still RAM-only.

The disposable `acl-runtime` phase renders its own policy into a fresh
per-run temporary directory, rather than overwriting the persistent
`acl-plan` evidence. This supports revised source/policy candidates without
requiring manual cleanup or weakening the fail-closed policy-file contract.

## Webhook activation profile composition

The new `startup-profile/probot-render.py` reuses the existing
`startup-profile/render.py` to declare the five-role VM1 group:
Redis, nginx, the pinned Logma lifecycle binary, the pinned Skymill HTTP
binary and Probot/Node. The Redis bootstrap/revocation hooks and private
service network remain those of the consolidated startup profile.
Skymill connects over the existing private nginx TCP proxy on DB 0;
the VM1 Redis server remains Unix-socket-only. Probot has independent
`probot_state` and `lifecycle_publish` Redis credentials; all runtime
passwords are read from mount-only files. Probot worker processing is
initially disabled and the public URL is a private placeholder until
real GitHub App authority and ingress configuration are installed.

`coreos-services/probot-credentials.py` emits a new private generation
using the existing ACL renderer. It retains the previously installed
Logma, Skymill, bootstrap, publisher and subscriber identities and the
Logma API key, and provisions separate Probot and observer credentials.
It refuses unknown ACL principals, inconsistent policy schema and
overwrites of an existing generation.

`#qualify-integration --scenario probot-webhook --phase service-profile`
runs these composition and credential tests inside Nix-Alpine. This
is a **render/credential contract qualification**, not live activation.
The existing CoreOS VM must be inventoried before a profile upgrade is
implemented. In particular, updating only the legacy two-service
`coreos-services/guest.sh` would conflict with an installed consolidated
startup profile and its Redis bootstrap/revocation hooks. Do not stop
or restart Redis just to pass these tests.
