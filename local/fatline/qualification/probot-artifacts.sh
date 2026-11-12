#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

[[ "$(uname -s)" == Linux && "$(uname -m)" == aarch64 ]] || {
  echo 'AGNI_PROBOT_ARTIFACTS=blocked reason=requires-arm64-nix-alpine' >&2
  exit 1
}
: "${AGNI_PROBOT_SOURCES:?Immutable application source manifest required}"
[[ -r "$AGNI_PROBOT_SOURCES" ]] || exit 1
root="${NIX_XD_PROBOT_WORKSPACES:-/workspaces}"
[[ "$root" == /workspaces ]] || exit 2
[[ "$(go env GOOS)" == linux ]] || exit 1
export GOOS=linux GOARCH=arm64 CGO_ENABLED=0
state="$HOME/.local/state/agni/probot-webhook"
mkdir -p "$state/gocache" "$state/modcache" "$state/gcroots"
export GOCACHE="$state/gocache" GOMODCACHE="$state/modcache"
work="$(mktemp -d "$state/build.XXXXXXXX")"
trap 'rm -rf -- "$work"' EXIT

source_record() {
  python3 - "$AGNI_PROBOT_SOURCES" "$1" <<'PY'
import json,re,sys
manifest=json.load(open(sys.argv[1],encoding="utf-8"))
if manifest.get("schema")!=1 or manifest.get("scenario")!="probot-webhook": raise SystemExit("Invalid scenario")
item=manifest["sources"][sys.argv[2]]
if not re.fullmatch(r"[a-z][a-z0-9-]{1,63}",item["checkout"]): raise SystemExit("Invalid checkout")
if not re.fullmatch(r"[0-9a-f]{40}",item["revision"]): raise SystemExit("Invalid commit")
print(item["checkout"]+" "+item["revision"])
PY
}

build_native() {
  local component="$1" command="$2" binary="$3" checkout revision src result root_name meta
  read -r checkout revision <<< "$(source_record "$component")"
  src="$root/$checkout"
  [[ -f "$src/go.mod" && -f "$src/.nix-xd-source-revision" ]] || exit 1
  [[ "$(< "$src/.nix-xd-source-revision")" == "$revision" ]] || {
    echo "AGNI_PROBOT_ARTIFACT=blocked source-mismatch=$component" >&2
    exit 1
  }
  (cd "$src" && go build -mod=readonly -trimpath -buildvcs=false -ldflags=-buildid= \
      -o "$work/$binary" "$command")
  meta="$(go version -m "$work/$binary")"
  grep -Fq 'GOOS=linux' <<< "$meta"
  grep -Fq 'GOARCH=arm64' <<< "$meta"
  result="$(nix-store --add "$work/$binary")"
  root_name="$state/gcroots/$component-$revision"
  if [[ ! -e "$root_name" ]]; then
    nix-store --realise --add-root "$root_name" "$result" >/dev/null
  else
    [[ "$(readlink -f "$root_name")" == "$result" ]] || {
      echo "AGNI_PROBOT_ARTIFACT=blocked root-conflict=$component" >&2
      exit 1
    }
  fi
  [[ -x "$result" ]] || exit 1
  printf 'AGNI_PROBOT_NATIVE_ARTIFACT=passed component=%s revision=%s store=%s\n' \
    "$component" "$revision" "$result"
}

build_native skymill ./cmd/skymill-http skymill-http
build_native logma ./cmd/api-lifecycle logma-lifecycle

read -r probot_checkout probot_revision <<< "$(source_record probot-runtime)"
probot="$root/$probot_checkout"
[[ -f "$probot/package-lock.json" && -f "$probot/package.json" ]] || exit 1
[[ "$(< "$probot/.nix-xd-source-revision")" == "$probot_revision" ]] || exit 1
node --check "$probot/src/skymill.js"
node --check "$probot/src/logma.js"
node - "$probot/package.json" "$probot/package-lock.json" <<'JS'
const fs = require('node:fs');
const [manifest, lock] = process.argv.slice(2).map(p => JSON.parse(fs.readFileSync(p, 'utf8')));
if (lock.lockfileVersion !== 3 || lock.packages?.['']?.name !== manifest.name ||
    JSON.stringify(lock.packages[''].dependencies) !== JSON.stringify(manifest.dependencies))
  throw Error('Probot lockfile mismatch');
console.log('AGNI_PROBOT_NODE_SOURCE=passed locked-manifest=true');
JS

mkdir -p "$work/probot"
cp -R "$probot/package.json" "$probot/package-lock.json" "$probot/src" "$work/probot/"
if [[ -d "$probot/router" ]]; then cp -R "$probot/router" "$work/probot/"; fi
export npm_config_cache="$state/npmcache"
export npm_config_userconfig=/dev/null npm_config_update_notifier=false
(cd "$work/probot" && npm ci --omit=dev --ignore-scripts --no-audit --no-fund)
(cd "$work/probot" && node -e 'for (const name of ["probot", "redis", "simple-router-builder"]) require.resolve(name)')
probot_store="$(nix-store --add "$work/probot")"
probot_root="$state/gcroots/probot-runtime-$probot_revision"
if [[ ! -e "$probot_root" ]]; then
  nix-store --realise --add-root "$probot_root" "$probot_store" >/dev/null
else
  [[ "$(readlink -f "$probot_root")" == "$probot_store" ]] || {
    echo 'AGNI_PROBOT_ARTIFACT=blocked root-conflict=probot-runtime' >&2
    exit 1
  }
fi
printf 'AGNI_PROBOT_NODE_ARTIFACT=passed revision=%s store=%s\n' "$probot_revision" "$probot_store"
printf 'AGNI_PROBOT_NATIVE_BUILD=passed system=aarch64-linux\n'
