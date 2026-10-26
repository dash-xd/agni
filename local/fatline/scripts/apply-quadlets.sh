#!/usr/bin/env bash
# Apply a Nix-rendered Fatline Quadlet bundle, restarting only changed units.
# Runs on the host as the same user that owns the rootless Podman systemd units.
set -Eeuo pipefail
[[ $# == 2 ]] || { echo "usage: $0 BUNDLE_DIR STATE_DIR" >&2; exit 2; }
bundle=$1 state=$2
[[ -d "$bundle/quadlets" && -d "$bundle/config" && -f "$bundle/metadata/components.json" ]] ||
  { echo "invalid Fatline bundle" >&2; exit 2; }
command -v flock >/dev/null
command -v systemctl >/dev/null
command -v podman >/dev/null
mkdir -p "$state"
exec 9>"$state/apply.lock"
flock -n 9 || { echo "Fatline apply already running" >&2; exit 1; }
dest="${XDG_CONFIG_HOME:-$HOME/.config}/containers/systemd"
mkdir -p "$dest"
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
  [[ "$name" =~ ^fatline-[a-z0-9-]+\.(container|network|volume)$ ]] ||
    { echo "unexpected Quadlet name: $name" >&2; exit 1; }
  if [[ -e "$dest/$name" && ! -f "$ledger" ]]; then
    echo "refusing to overwrite unmanaged Quadlet $dest/$name" >&2
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
done
changed=()
for file in "$bundle"/quadlets/*; do
  [[ -f "$file" ]] || continue
  name=${file##*/}
  if [[ ! -f "$dest/$name" ]] || ! cmp -s "$file" "$dest/$name"; then
    changed+=("$name")
  fi
done
if (( ${#changed[@]} == 0 )); then
  echo "PASS: Fatline Quadlets already converged"
  exit 0
fi
backup=$(mktemp -d "$state/backup.XXXXXXXX")
rollback() {
  code=$?
  if (( code != 0 )); then
    echo "FAIL: apply interrupted; restoring previous Quadlet files" >&2
    for name in "${changed[@]}"; do
      if [[ -f "$backup/$name" ]]; then cp "$backup/$name" "$dest/$name"; else rm -f "$dest/$name"; fi
    done
    systemctl --user daemon-reload || true
  fi
  rm -rf "$backup"
}
trap rollback EXIT
for name in "${changed[@]}"; do
  [[ ! -f "$dest/$name" ]] || cp "$dest/$name" "$backup/$name"
  install -m 600 "$bundle/quadlets/$name" "$dest/$name"
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
    echo "PASS: updated fatline-$component without replacing other providers"
  done
done
printf '%s\n' "$bundle"/quadlets/* | sed 's|.*/||' > "$ledger.tmp"
mv "$ledger.tmp" "$ledger"
cp "$bundle/metadata/components.json" "$state/components.json"
echo "PASS: Fatline Quadlet apply completed"
