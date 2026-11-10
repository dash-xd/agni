# CoreOS host-link gate

This is the first transport/security gate toward a Fatline deployment. It is not
an authorization to promote the old candidate images or a full Logma/Skymill gate.
Agni owns templates, source pins, and ACL generation. nix.xd owns host transport,
root retention, and the Make interface. The reusable subscriber is compiled from
Logma's maintained `serverless/pubsub` package, with its Ready acknowledgement;
it does not revive the older standalone client without named-user support.

One CoreOS VM runs independently supervised rootless Redis and nginx Quadlets.
Redis is RAM-only, 40 MiB/noeviction, port 0, default user off, one logical DB.
nginx forwards loopback-published TCP to a 0600 Unix socket in a 0700 scope-private
directory. It receives a read-only socket-directory mount, not Redis credentials.
The Redis ACL file is runtime-generated, mode 0600, and mounted only into Redis.
The approved qualification publisher receives its own credential files only.
All containers have read-only rootfs/store, no capabilities, no-new-privileges,
and non-root UID 1000 with the already qualified keep-id mapping. The existing
9P model requires SELinux label separation disabled for these mounts; DAC and
mount namespace checks are explicit and do not imply SELinux qualification.

The host subscriber is a pure-Go Darwin binary built by the Linux Nix owner. It
connects through an SSH loopback forward to nginx, never to a Redis TCP listener.
This requires neither host Nix nor host Go and copies only the portable client,
not a Nix closure. The same client has a native Linux output for guest probes.
Credentials are sandbox-only high-entropy values generated at runtime, outside
Nix derivations. Production delivery/rotation stays with Smoke.

The test permits a scoped key write/read for the publisher and a named channel
subscription for the subscriber, while denying foreign keys/channels, subscriber
publication/key reads, SELECT 1, ACL, CONFIG and FUNCTION access. A deliberately
different container UID must get EACCES connecting to the Unix socket. TCP still
requires the Redis ACL: nginx transports RESP and does not substitute an auth
identity. DB 0 is an organizational choice; Pub/Sub scoping comes from channel
prefixes and ACLs, not database numbers. This gate does not prove kernel-level
isolation from the trusted rootless Podman owner or root.

Scope IDs, unit names, runtime directories, and ports are instance-specific. The
first output is host-link-vm1; a second VM profile should use a distinct scope and
endpoint. Cross-VM Unix sockets are not a transport. Extend the same TCP/nginx
contract for the second VM after this gate passes, then attach Logma API lifecycle,
Function reconciliation, and Skymill using package-owned production ACL contracts.
