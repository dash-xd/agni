#!/usr/bin/env bash
set -euo pipefail

# Run from the flake directory, as mounted by Nix-Alpine.
# Keep mutable Git checkouts outside the immutable Nix store.
ROOT="${FATLINE_WORKSPACE:-$PWD/.fatline-workspace}"
SOURCES="$ROOT/sources"
LOCK="$ROOT/refs.lock"
mkdir -p "$ROOT"

# Branches are inputs for the initial bootstrap only. The resulting exact
# commit SHAs are saved in refs.lock and used for all subsequent commands.
names=(logma prajapati smoke)
repos=(xd-dash/logma xd-dash/prajapati xd-dash/smoke)
branches=(codex/group-strength-resources codex/fatline-authz-integration integration/smoke-reconcile-20261016)

bootstrap() {
  mkdir -p "$SOURCES"
  if [[ -e "$LOCK" ]]; then
    echo "Existing pin file: $LOCK" >&2
    echo "Remove it explicitly to rebootstrap different revisions." >&2
    exit 1
  fi
  local tmp
  tmp="$(mktemp "$ROOT/refs.lock.XXXXXX")"
  trap 'rm -f "$tmp"' RETURN
  for i in "${!names[@]}"; do
    local name="${names[$i]}" path="$SOURCES/${names[$i]}"
    if [[ ! -d "$path/.git" ]]; then
      git clone --branch "${branches[$i]}" --single-branch "https://github.com/${repos[$i]}.git" "$path"
    fi
    if [[ -n "$(git -C "$path" status --porcelain)" ]]; then
      echo "Dirty checkout: $path" >&2
      exit 1
    fi
    local sha
    sha="$(git -C "$path" rev-parse HEAD)"
    printf '%s %s\n' "$name" "$sha" >> "$tmp"
    echo "$name pinned at $sha"
  done
  mv "$tmp" "$LOCK"
  echo "Wrote $LOCK"
}

preflight() {
  [[ -f "$LOCK" ]] || { echo "Run bootstrap first" >&2; exit 1; }
  local name sha path current
  for name in "${names[@]}"; do
    sha="$(awk -v n="$name" '$1 == n {print $2}' "$LOCK")"
    [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || { echo "Invalid/missing pin: $name" >&2; exit 1; }
    path="$SOURCES/$name"
    [[ -d "$path/.git" ]] || { echo "Missing checkout: $path" >&2; exit 1; }
    current="$(git -C "$path" rev-parse HEAD)"
    [[ "$current" == "$sha" ]] || { echo "Revision mismatch: $name" >&2; exit 1; }
    [[ -z "$(git -C "$path" status --porcelain)" ]] || { echo "Dirty checkout: $name" >&2; exit 1; }
    echo "$name $sha"
  done
}

build() {
  preflight
  for name in "${names[@]}"; do
    echo "Building $name"
    (cd "$SOURCES/$name" && GOWORK=off go build ./...)
  done
}

qualify() {
  preflight
  echo "Prajapati authorization package"
  (cd "$SOURCES/prajapati" && GOWORK=off go test ./authz)
  echo "Logma graph model"
  (cd "$SOURCES/logma" && GOWORK=off go test ./internal/pubsubmodel)
  echo "Smoke package compilation"
  (cd "$SOURCES/smoke" && GOWORK=off go build ./...)
  echo "Baseline complete. Cross-project HTTP enforcement is NOT tested yet."
}

qualify_integration() {
  preflight
  echo "Integration gate requires Logma HTTP project-authorization tests and Redis persistence tests." >&2
  echo "These tests are not implemented on the pinned Logma revision; refusing to report a false pass." >&2
  return 1
}

case "${1:-}" in
  bootstrap|preflight|build|qualify) "$1" ;;
  qualify-integration) qualify_integration ;;
  *) echo "Usage: fatline.sh {bootstrap|preflight|build|qualify|qualify-integration}" >&2; exit 2 ;;
esac
