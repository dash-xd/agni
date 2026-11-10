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
