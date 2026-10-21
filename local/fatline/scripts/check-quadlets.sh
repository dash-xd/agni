#!/usr/bin/env bash
set -euo pipefail
base="${FATLINE_QUADLET_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../systemd" && pwd)}"
fail() { printf 'Fatline Quadlet preflight: %s\n' "$*" >&2; exit 1; }
for file in fatline-redis.container fatline-logma.container fatline-skymill.container redis.conf; do
  [[ -s "$base/$file" ]] || fail "missing $file"
done
grep -Eq '^port[[:space:]]+0$' "$base/redis.conf" || fail "TCP must be disabled"
grep -Eq '^unixsocket[[:space:]]+/run/redis/redis.sock$' "$base/redis.conf" || fail "socket path mismatch"
grep -Eq '^maxmemory[[:space:]]+40mb$' "$base/redis.conf" || fail "40 MiB limit missing"
grep -Eq '^maxmemory-policy[[:space:]]+noeviction$' "$base/redis.conf" || fail "noeviction missing"
grep -Eq '^aclfile[[:space:]]+/etc/redis/users.acl$' "$base/redis.conf" || fail "ACL policy not required"
grep -Eq '^save[[:space:]]+""$' "$base/redis.conf" || fail "RDB persistence must be disabled"
grep -Eq '^appendonly[[:space:]]+no$' "$base/redis.conf" || fail "AOF persistence must be disabled"
grep -Eq '^Network=none$' "$base/fatline-redis.container" || fail "Redis must have no container network"
for component in logma skymill; do
  file="$base/fatline-$component.container"
  grep -Eq '^Requires=fatline-redis.service$' "$file" || fail "$component missing Requires"
  grep -Eq '^After=fatline-redis.service$' "$file" || fail "$component missing After"
  grep -Fq 'Volume=/run/fatline/redis:/run/redis:' "$file" || fail "$component missing shared socket"
done
for file in "$base"/*.container; do
  if grep -Eq '^Image=.*:latest$' "$file"; then fail "floating latest image in $file"; fi
done
printf '%s\n' 'Fatline Quadlet static invariants PASS (runtime not qualified)'
