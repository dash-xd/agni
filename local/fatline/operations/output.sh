#!/usr/bin/env bash
# Extract exactly one nonempty machine-readable value from a logged operation.
agni_capture_value() {
  local key="$1" file="$2"
  [[ "$key" =~ ^[A-Z][A-Z0-9_]*$ && -f "$file" ]] || return 1
  awk -v prefix="$key=" '
    index($0, prefix) == 1 {
      found++
      value=substr($0, length(prefix)+1)
    }
    END {
      if (found != 1 || value == "") exit 1
      print value
    }
  ' "$file"
}
