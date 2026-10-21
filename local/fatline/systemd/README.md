# Fatline systemd / Podman Quadlet candidates

Agni owns the service composition. These are **source templates only**; they are not installed, started, or qualified by this branch.

- `fatline-redis.container` owns a RAM-only 40 MiB `noeviction` Redis 7.2.5 instance with TCP disabled and a Unix socket at `/run/redis/redis.sock` inside the container.
- `redis.conf` requires `/etc/redis/users.acl`. **Do not create an unrestricted default ACL.** Reconcile the existing Marai/Smoke Redis ACL policy and provision independently scoped Logma/Skymill credentials using the established authority workflow.
- `fatline-logma.container` and `fatline-skymill.container` require `fatline-redis.service` and mount the same host socket directory. Their `localhost/fatline-*:qualified` image tags are **unresolved placeholders**; deployment must substitute qualified digest-pinned images and verified environment schemas.
- The templates currently assume a rootful CoreOS system manager and shared socket path. Socket UID/GID, SELinux relabeling, Podman mount access, and consumer process privileges must be qualified before installation. Mounting a Unix socket does not itself establish authorization.
- `/run/fatline/redis` is the host socket directory; `/etc/fatline/redis/redis.conf` and `/etc/fatline/redis/users.acl` are provisioned host inputs. The socket directory must be accessible to both provider containers with least privilege.
- No test may issue `FLUSHDB` or `FLUSHALL` against this shared service. Integration probes require unique test namespaces, scoped cleanup, and verified ACL denial of cross-tenant keys and administration.

`scripts/fatline.sh qualify-integration` now fails closed if the managed socket or credentials are missing and still deliberately fails after its connectivity checks. It does **not** yet prove provider integration.

**Do not install these units in production yet.** Reconcile them with Agni's ignition generator, Smoke's Quadlet installation workflow, actual Nix-built provider images, and existing ACL policy. Next gates: Podman Quadlet generator validation, container startup, socket access, ACL denial, Logma graph tests, Skymill crash/reclaim and HTTP restart tests, and Redis restart dependency recovery.
