#!/usr/bin/env bash
set -Eeuo pipefail

workspace_root="$(realpath "${1:?workspace root required}")"
agni_checkout="${2:?Agni checkout path required}"
agni_rev="${3:?pinned Agni revision required}"
nix_checkout="${4:?Nix-Alpine checkout path required}"
nix_rev="${5:?pinned Nix-Alpine revision required}"
resource_output="$(realpath -m "${6:?profile output directory required}")"
workspace_files="${7:-}"
console_login="${8:-0}"
agni_dir="$(realpath "$workspace_root/$agni_checkout")"
nix_dir="$(realpath "$workspace_root/$nix_checkout")"
profile="$agni_dir/qemu/coreos-live/profiles/astrochicken"

for pair in "Agni:$agni_dir:$agni_rev" "Nix-Alpine:$nix_dir:$nix_rev"; do
  IFS=: read -r label source revision <<<"$pair"
  [[ "$revision" =~ ^[0-9a-f]{40}$ && "$(git -C "$source" rev-parse HEAD)" == "$revision" ]] || {
    echo "$label checkout does not match its pinned revision" >&2
    exit 2
  }
  [[ -z "$(git -C "$source" status --porcelain)" ]] || {
    echo "$label checkout must be clean and committed" >&2
    exit 2
  }
done
[[ "$agni_dir/" == "$workspace_root/"* && "$nix_dir/" == "$workspace_root/"* ]] || {
  echo "Agni and Nix-Alpine checkouts must remain beneath the shared workspace" >&2
  exit 2
}
[[ "$resource_output/" == "$workspace_root/"* && "$resource_output" != "$workspace_root" ]] || {
  echo "Profile output must be a child of the shared workspace" >&2
  exit 2
}
[[ "$console_login" == 0 || "$console_login" == 1 ]] || {
  echo "Console login must be 0 or 1" >&2
  exit 2
}
[[ -f "$profile/butane/astrochicken.bu" && -d "$profile/resources/astrochicken" ]] || {
  echo "Agni Astrochicken profile inputs are incomplete" >&2
  exit 2
}

parent="$(dirname "$resource_output")"
mkdir -p "$parent"
staging="$(mktemp -d "$parent/.astrochicken-inputs.XXXXXX")"
backup="${resource_output}.previous.$$"
cleanup() {
  [[ -z "${staging:-}" || ! -d "$staging" ]] || rm -rf -- "$staging"
  if [[ -d "$backup" && ! -e "$resource_output" ]]; then mv -- "$backup" "$resource_output"; fi
  [[ ! -e "$backup" ]] || rm -rf -- "$backup"
}
trap cleanup EXIT

cp -a "$profile/resources/." "$staging/"
mkdir -p "$staging/astrochicken"
git -C "$nix_dir" archive --format=tar "$nix_rev" | gzip -n > "$staging/astrochicken/nix-alpine-source.tar.gz"
printf '%s\n' "$nix_rev" > "$staging/astrochicken/nix-alpine-revision"

mkdir -p "$staging/astrochicken/workspace-imports"
entries="$staging/.extra-storage-files"
: > "$entries"
declare -A destinations=()
count=0
IFS=' ' read -r -a requested_files <<< "$workspace_files"
for relative_path in "${requested_files[@]}"; do
  [[ -n "$relative_path" ]] || continue
  [[ "$relative_path" != /* && "$relative_path" != *$'\n'* && "$relative_path" != *$'\t'* ]] || {
    echo "Workspace resource must be a relative path without whitespace: $relative_path" >&2
    exit 2
  }
  case "/$relative_path/" in */../*|*/./*) echo "Workspace resource path must be normalized: $relative_path" >&2; exit 2 ;; esac
  [[ "$relative_path" =~ ^[A-Za-z0-9._/-]+$ ]] || { echo "Unsupported workspace resource path: $relative_path" >&2; exit 2; }
  source_file="$(realpath "$workspace_root/$relative_path")"
  [[ "$source_file/" == "$workspace_root/"* && -f "$source_file" && ! -L "$workspace_root/$relative_path" ]] || {
    echo "Workspace resource must be a regular file beneath WORKSPACES: $relative_path" >&2
    exit 2
  }
  case "$relative_path" in nix-alpine/*|agni/*|astrochicken-flake/*) echo "Workspace resource path is reserved: $relative_path" >&2; exit 2 ;; esac
  [[ -z "${destinations[$relative_path]:-}" ]] || { echo "Duplicate workspace resource path: $relative_path" >&2; exit 2; }
  destinations[$relative_path]=1
  count=$((count + 1))
  resource_path="astrochicken/workspace-imports/$relative_path"
  mkdir -p "$staging/$(dirname "$resource_path")"
  cp -- "$source_file" "$staging/$resource_path"
  printf '    - path: /etc/astrochicken/workspace-imports/%s\n      mode: 0644\n      contents:\n        local: %s\n' "$relative_path" "$resource_path" >> "$entries"
done

if [[ "$console_login" == 1 ]]; then
  cat >> "$entries" <<'EOF'
    - path: /etc/astrochicken/console-enabled
      mode: 0444
      contents:
        inline: enabled
EOF
fi
awk -v extra="$entries" '
  $0 == "  # ASTROCHICKEN_EXTRA_STORAGE_FILES" {
    while ((getline line < extra) > 0) print line
    close(extra)
    next
  }
  { print }
' "$profile/butane/astrochicken.bu" > "$staging/astrochicken-generated.bu"
grep -q '^  # ASTROCHICKEN_EXTRA_STORAGE_FILES$' "$profile/butane/astrochicken.bu" || {
  echo "Agni Astrochicken profile is missing its resource insertion point" >&2
  exit 2
}
rm -f -- "$entries"

if [[ -e "$resource_output" ]]; then
  [[ -d "$resource_output" && ! -L "$resource_output" ]] || { echo "Refusing to replace a non-directory profile output" >&2; exit 2; }
  mv -- "$resource_output" "$backup"
fi
mv -- "$staging" "$resource_output"
staging=""
rm -rf -- "$backup"
echo "PASS: Agni Astrochicken profile assembled from pinned Agni $agni_rev and Nix-Alpine $nix_rev"
echo "Workspace files embedded: $count"
echo "Console login enabled: $console_login"
