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

## Agni-owned guest inventory through generic Nix-Alpine transport

`#vm1-guest-check` is an immutable Nix package containing `guest.sh`.
It owns VM1 application-specific inventory and native artifact read checks,
but does **not** install services, change Redis ACLs, restart processes,
or generate application credentials.

Nix-Alpine's generic `guest-app` host adapter takes a pinned flake,
a target package, the exact source SHA, and opaque JSON-array arguments.
Use the normal host-owned SSH identity/known_hosts for the existing guest.
No Fatline or Probot target, phase, or role name is encoded in nix.xd's
default Makefile.

Example from the dated nix.xd checkout (substitute the pinned Agni SHA):

```sh
make guest-app FLAKE=agni20261112/local/fatline \
  TARGET='#vm1-guest-check' GUEST_APP_REV=<exact-agni-sha> \
  ARGS_JSON='["inventory","fatline-arm-vm1"]' \
  COREOS_SSH_KEY="$HOME/.ssh/starwisp-test" \
  COREOS_SSH_PORT=2222 COREOS_PROFILE=starwisp
```

For the `store-check` action, supply the exact three immutable store
artifact paths and source revisions, plus Node, in this order:
`["store-check", scope, skymillStore, skymillSHA, logmaStore, logmaSHA,
probotStore, probotSHA, nodeStoreExecutable]`. Those values must come
from the Agni artifact manifest; never guess them. This check remains
read-only and validates guest 9P visibility, not service activation.

The new application-owned path replaces the two obsolete Probot-specific
host preflight targets. Other, older Fatline host controllers remain available
only for explicit recovery of generations created by those controllers,
until their Agni-owned replacement qualifies against the live VM.

## Immutable Probot guest handoff (November 2026)

`#qualify-integration --scenario probot-webhook --phase guest-bundle`
reruns the pinned source, ARM64 artifacts, ACL and guest planners. It copies
**only non-secret** artifacts.json, sources.json, policy.json, guest-plan.json
and artifacts.tsv into a SHA256-verified directory, imports that candidate
with `nix-store --add`, and retains a GC root in the Nix-Alpine writer.
The output `AGNI_PROBOT_GUEST_BUNDLE_PATH` selects an exact store object.

`#vm1-probot-guest-stage` is an Agni-owned guest app executable via the
generic nix.xd `guest-app` transport. Actions:

- `verify SCOPE BUNDLE_STORE`: read-only guest-side bundle checksums and
  exact Skymill, Logma, Probot Node files + Node executable visibility
  through the existing 9P mount. Does not touch Redis or service files.
- `stage SCOPE BUNDLE_STORE`: additionally requires the **already installed**
  base startup-profile manifest and private service credentials. Uses the
  existing guest credential generator, retains publisher/subscriber ACL
  identities and renders a new privately stored candidate with
  `probot-guest-stage.sh`. Does not activate services or restart Redis.
  Its state path is keyed by the bundle, base profile and current ACL hashes.
- `status SCOPE`: delegates to Agni's installed startup-profile runtime
  status path; it cannot manufacture an installed profile.
- `activate SCOPE BUNDLE_STORE`: currently fails closed. A real GitHub App
  Binding and delivery ingress qualification must precede activation.

The existing VM1 preflight does **not** prove that a consolidated base
startup profile is installed. A missing base profile is a dependency,
not an instruction to fabricate manifests or restart the existing Redis.
The candidate transfer is OS-neutral as long as the selected guest exposes
the qualified Nix store paths; the current staging implementation uses the
Fedora CoreOS Podman/Quadlet adapter and must be adapted and qualified
independently before reuse on Grml.

## Legacy VM1 startup-profile adoption assessment

When `inventory` reports `profile=absent` but the existing host-link Redis
and two application Quadlets remain active, **do not write an invented
`services/profile/manifest.json` or invoke `install-probot`**. The legacy
two-service guest installer does not have the consolidated startup-profile
bootstrap and systemd lifecycle hooks.

Agni's `#vm1-probot-guest-stage` package now accepts
`adopt-plan fatline-arm-vm1 /nix/store/<sha>-candidate`.
This verifies the exact bundle and runs a separate read-only adoption assessor
inside rootless Podman. It observes host systemd states without restarting
anything, reads existing Quadlet definitions, fingerprints their Nix store
references and current Redis/host-link ACL identities, and writes only a
private content-addressed assessment JSON under
`services/adoption-assessments/`. No ACL contents or credentials appear in
the assessment. The output distinguishes a complete consolidated profile,
a legacy runtime requiring migration, and missing runtime dependencies.

`AGNI_PROBOT_ADOPTION_ASSESSMENT=passed` means the observation completed,
**not** that migration or activation has passed. An absent consolidated
profile remains an explicit migration blocker. The next implementation
must select a compatible immutable base profile from verified store and
credential provenance, then qualify a staged handover prior to any live
systemd/Redis changes. The existing `stage` action remains fail-closed.

## Pinned adoption evidence review

`#vm1-probot-guest-stage` supports `adopt-review SCOPE BUNDLE_STORE
ASSESSMENT_SHA256`. It verifies the existing content-addressed adoption
evidence and selected bundle in a read-only rootless container, and prints
the current Quadlet store references, selected application store paths,
service activity and presence-only credential prerequisites. It refuses
evidence from another bundle. The action neither mutates the current
profile nor restarts Redis.

A passing `AGNI_PROBOT_ADOPTION_REVIEW` is a planning result only. The
migration must still qualify a compatible base startup-profile generation,
including required service credentials and lifecycle hooks, before private
staging or explicit activation is permitted.

## Controlled legacy VM1 migration staging (November 2026)

`#vm1-probot-guest-stage` now supports
`adopt-stage fatline-arm-vm1 BUNDLE_STORE ASSESSMENT_SHA256`. This is
**not** the legacy `stage` action; it works when no consolidated profile
has yet been installed.

The stage action verifies the exact guest candidate, checks that all
four original services remain active, and takes the scoped lifecycle lock.
A separate rootless Podman process receives read-only mounts for the
previous ACL, old private role credentials, Quadlets and assessment, and
the authoritative read-only Nix store. It uses the assessment hashes to
reject any changed Redis ACL or Quadlet, resolves the actual Redis/nginx
executables and loopback proxy port, and obtains the bootstrap probe,
startup-profile bundle and fallback static rootfs archive from Agni's
immutable Nix package (not user-selected host commands).

The generated spec uses the observed CoreOS rootless home path
(`/var/home/wisp` or `/home/wisp`), not a hard-coded home in the new
migration resolver. The existing guest-private generator retains
publisher/subscriber ACL identities plus Logma, Skymill and bootstrap
credential values and produces scoped Probot credentials and five-role
Quadlets. Staging validates read-only Nix mounts, private credential
mounts, dependency edges and unpublished application ports.

The operation writes only a private generation under
`services/probot-migrations/`, keyed by the exact assessment digest
and bundle store identity. It never changes active ACLs, systemd
definitions, the installed startup profile or Redis. A repeated
attempt refuses the existing generation rather than silently reusing
potentially stale credentials. A failed partial generation must be
reviewed before another attempt.

The generated profile still has
`PROBOT_RUNTIME_WORKER_ENABLED=false`, and activating it remains
explicitly blocked pending GitHub App Binding and ingress qualification.
Further guest runtime qualification must verify the complete migration
handoff before an Agni-owned `activate` action is permitted to stop
or replace the legacy services.
