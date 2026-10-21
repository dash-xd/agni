# Local Fatline service composition (systemd user manager)

This directory specifies the planned persistent, systemd-owned Redis service for a Fatline scope. It is **not** a test-script-managed Redis process.

No service units have been installed or qualified by this change. A deployment must supply a scope-specific Redis configuration, socket directory, scoped ACL file and secrets using its existing Smoke/Quadlet authority path.

Service ordering:

- fatline-redis.service owns the Redis process and its Unix socket.
- fatline-logma.service and fatline-skymill.service must use Requires= and After= against fatline-redis.service.
- Providers must authenticate as distinct Redis ACL users over the socket.
- Destructive integration fixtures must never use FLUSHDB on the shared service.

The integration gate in scripts/fatline.sh now **fails closed** until the deployment provides FATLINE_REDIS_SOCKET, FATLINE_LOGMA_REDIS_USER/PASSWORD, and FATLINE_SKYMILL_REDIS_USER/PASSWORD, and until the credential-aware non-destructive provider probes exist.

The intended memory profile is 40 MiB, RAM-only and noeviction. Its presence here is a target; qualification must verify the live service, not rely on this document.
