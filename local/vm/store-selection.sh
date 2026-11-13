#!/usr/bin/env bash
# Read-only selection: caller-specified nonempty volume takes precedence;
# otherwise reuse the exact identity recorded in an existing VM manifest.
agni_vm_select_store_volume() {
  local manifest="$1" selected="${COREOS_NIX_STORE_VOLUME:-}" count recorded
  if [[ -f "$manifest" ]]; then
    count="$(grep -c '^shared_nix_volume=' "$manifest" || true)"
    [[ "$count" == 0 || "$count" == 1 ]] || {
      echo 'Ambiguous shared Nix store in VM manifest' >&2
      return 1
    }
    recorded="$(sed -n 's/^shared_nix_volume=//p' "$manifest")"
    if [[ -z "$selected" && -n "$recorded" && "$recorded" != none ]]; then
      selected="$recorded"
      printf 'AGNI_VM_STORE_SELECTION=manifest volume=%s\n' "$selected" >&2
    fi
  fi
  [[ -z "$selected" || "$selected" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] || {
    echo 'Invalid shared Nix store selection' >&2
    return 1
  }
  printf '%s\n' "$selected"
}
