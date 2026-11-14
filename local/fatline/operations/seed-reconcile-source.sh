#!/usr/bin/env bash
set -Eeuo pipefail

source_revision=1a0ce1f3684c120a8a800e7e63c45f0780bdda09
destination=/workspaces/probot-reconcile20261114
object_root="$HOME/.local/state/smoke/ghxd/objects"

[[ -d /workspaces && -w /workspaces ]] || {
  echo 'AGNI_RECONCILE_SOURCE=blocked reason=workspace-not-writable' >&2
  exit 1
}
if [[ ! -e "$destination" ]]; then
  command -v smoke >/dev/null || {
    echo 'AGNI_RECONCILE_SOURCE=blocked reason=smoke-cli-unavailable' >&2
    exit 1
  }
  smoke ghxd worktree seed \
    --repository xd-dash/probot-runtime \
    --sha "$source_revision" \
    --destination "$destination" \
    --object-root "$object_root"
fi

[[ -e "$destination/.git" &&
   "$(git -C "$destination" rev-parse HEAD)" == "$source_revision" &&
   -z "$(git -C "$destination" status --porcelain)" &&
   -z "$(git -C "$destination" symbolic-ref -q HEAD || true)" ]] || {
  echo 'AGNI_RECONCILE_SOURCE=blocked reason=source-not-pinned-clean-detached' >&2
  exit 1
}

echo "AGNI_RECONCILE_SOURCE_SEED=passed authority=smoke-ghxd sha=$source_revision"
