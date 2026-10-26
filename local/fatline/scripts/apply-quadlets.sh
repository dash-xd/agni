#!/usr/bin/env bash
# Apply a Nix-rendered Fatline Quadlet bundle, restarting only changed units.
# Runs on the host as the same user that owns the rootless Podman systemd units.
set -Eeuo pipefail
[[ $# == 2 || ( $# == 3 && "$3" == "--preflight" ) ]] || { echo "usage: $0 BUNDLE_DIR STATE_DIR [--preflight]" >&2; exit 2; }
preflight_only=false
[[ "${3:-}" != --preflight ]] || preflight_only=true
bundle=$1 state=$2
[[ -d "$bundle/quadlets" && -d "$bundle/config" && -f "$bundle/metadata/components.json" ]] ||
  { echo "invalid Fatline bundle" >&2; exit 2; }
command -v flock >/dev/null
command -v systemctl >/dev/null
command -v podman >/dev/null
[[ "$preflight_only" == true ]] || mkdir -p "$state"
exec 9>"$state/apply.lock"
flock -n 9 || { echo "Fatline apply already running" >&2; exit 1; }
dest="${XDG_CONFIG_HOME:-$HOME/.config}/containers/systemd"
[[ "$preflight_only" == true ]] || mkdir -p "$dest"
service_dest="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
[[ "$preflight_only" == true ]] || mkdir -p "$service_dest"
unit_dest() { case "$1" in *.service) printf "%s/%s" "$service_dest" "$1";; *) printf "%s/%s" "$dest" "$1";; esac; }
# Never silently take ownership of another deployment's Quadlets.
ledger="$state/managed-units"
if [[ -f "$ledger" ]]; then
  while IFS= read -r name; do
    [[ -z "$name" || -f "$bundle/quadlets/$name" ]] ||
      { echo "refusing implicit removal of managed unit $name" >&2; exit 1; }
  done < "$ledger"
fi
for file in "$bundle"/quadlets/*; do
  [[ -f "$file" ]] || continue
  name=${file##*/}
  [[ "$name" =~ ^fatline-[a-z0-9-]+\.(container|network|volume|service)$ ]] ||
    { echo "unexpected Quadlet name: $name" >&2; exit 1; }
  target=$(unit_dest "$name")
  if [[ -e "$target" ]] && { [[ ! -f "$ledger" ]] || ! grep -Fxq -- "$name" "$ledger"; }; then
    echo "refusing to overwrite unmanaged unit $target" >&2
    exit 1
  fi
done
# Validate image availability before mutating host configuration.
for name in redis logma skymill; do
  file="$bundle/quadlets/fatline-$name.container"
  [[ -f "$file" ]] || { echo "missing $file" >&2; exit 1; }
  image=$(sed -n 's/^Image=//p' "$file")
  [[ -n "$image" && "$image" != *$'\n'* ]] || { echo "invalid image for $name" >&2; exit 1; }
  podman image exists "$image" || { echo "image not loaded: $image" >&2; exit 1; }
  [[ "$image" != localhost/fatline/*:2026.10.21 ]] || { echo "reserved image reference not deployable: $image" >&2; exit 1; }
  [[ "$image" != *:candidate && "$image" != *:latest ]] || { echo "mutable image tag forbidden: $image" >&2; exit 1; }
done
changed=()
for file in "$bundle"/quadlets/*; do
  [[ -f "$file" ]] || continue
  name=${file##*/}
  target=$(unit_dest "$name")
  if [[ ! -f "$target" ]] || ! cmp -s "$file" "$target"; then
    changed+=("$name")
  fi
done
if [[ "$preflight_only" == true ]]; then
  printf "Preflight changes: %s\n" "${changed[*]:-none}"
  for component in redis logma skymill; do
    readiness="${XDG_CONFIG_HOME:-$HOME/.config}/fatline/readiness/$component"
    [[ -x "$readiness" ]] || { echo "missing readiness probe: $readiness" >&2; exit 1; }
  done
  reconcile="${XDG_CONFIG_HOME:-$HOME/.config}/fatline/reconcile"
  [[ -x "$reconcile" ]] || { echo "missing reconciliation executable: $reconcile" >&2; exit 1; }
  echo "PASS: preflight only; no units changed"
  exit 0
fi
if (( ${#changed[@]} == 0 )); then
  echo "PASS: Fatline Quadlets already converged"
  exit 0
fi
# Record identities of unaffected running providers; a scoped upgrade must not
# silently replace them through dependency propagation.
declare -A before_ids=()
for component in redis logma skymill; do
  if systemctl --user is-active --quiet "fatline-$component.service"; then
    before_ids[$component]=$(podman inspect "fatline-$component" --format '{{.Id}}' 2>/dev/null || true)
  fi
done
backup=$(mktemp -d "$state/backup.XXXXXXXX")
rollback() {
  code=$?
  if (( code != 0 )); then
    echo "FAIL: apply interrupted; restoring previous Quadlet files" >&2
    for name in "${changed[@]}"; do
      target=$(unit_dest "$name")
      if [[ -f "$backup/$name" ]]; then cp "$backup/$name" "$target"; else rm -f "$target"; fi
    done
    systemctl --user daemon-reload || true
    for component in redis logma skymill; do
      for name in "${changed[@]}"; do
        if [[ "$name" == "fatline-$component.container" && -f "$backup/$name" ]]; then
          systemctl --user restart "fatline-$component.service" || echo "ROLLBACK FAILED: fatline-$component" >&2
        fi
      done
    done
  fi
  rm -rf "$backup"
}
trap rollback EXIT
for name in "${changed[@]}"; do
  target=$(unit_dest "$name")
  [[ ! -f "$target" ]] || cp "$target" "$backup/$name"
  install -m 600 "$bundle/quadlets/$name" "$target"
done
systemctl --user daemon-reload
# Network definition changes require an explicit migration, not an accidental
# restart of every provider on a live host.
for name in "${changed[@]}"; do
  case "$name" in
    *.network|*.volume)
      if [[ -f "$backup/$name" ]]; then
        echo "network/volume change requires an explicit migration: $name" >&2
        exit 1
      fi ;;
  esac
done
# Restart only changed providers. No cascading PartOf/BindsTo relationships.
for component in redis logma skymill; do
  for name in "${changed[@]}"; do
    [[ "$name" == "fatline-$component.container" ]] || continue
    systemctl --user restart "fatline-$component.service"
    systemctl --user is-active --quiet "fatline-$component.service" ||
      { echo "failed to start fatline-$component" >&2; exit 1; }
    readiness="${XDG_CONFIG_HOME:-$HOME/.config}/fatline/readiness/$component"
    [[ -x "$readiness" ]] || { echo "missing executable readiness probe: $readiness" >&2; exit 1; }
    ready=false
    for attempt in $(seq 1 20); do
      if "$readiness"; then ready=true; break; fi
      sleep 1
    done
    [[ "$ready" == true ]] || { echo "readiness failed: fatline-$component" >&2; exit 1; }
    if [[ "$component" == redis ]]; then
      systemctl --user start fatline-reconcile.service || { echo "Redis reconciliation failed" >&2; exit 1; }
    fi
    echo "PASS: updated fatline-$component without replacing other providers"
  done
done
for component in redis logma skymill; do
  [[ -n "${before_ids[$component]:-}" ]] || continue
  changed_provider=false
  for name in "${changed[@]}"; do
    [[ "$name" != "fatline-$component.container" ]] || changed_provider=true
  done
  if [[ "$changed_provider" == false ]]; then
    after_id=$(podman inspect "fatline-$component" --format '{{.Id}}' 2>/dev/null || true)
    [[ "$after_id" == "${before_ids[$component]}" ]] || {
      echo "FAIL: unchanged fatline-$component was replaced during apply" >&2
      exit 1
    }
  fi
done
printf '%s\n' "$bundle"/quadlets/* | sed 's|.*/||' > "$ledger.tmp"
mv "$ledger.tmp" "$ledger"
cp "$bundle/metadata/components.json" "$state/components.json"
echo "PASS: Fatline Quadlet apply completed"
