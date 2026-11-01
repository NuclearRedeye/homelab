#!/usr/bin/env bash
# Fails if a Secret could reach this public repo unencrypted: every Secret must
# live in a *.sops.yaml file, and every *.sops.yaml file must be encrypted.
#
# Usage: check-encryption.sh [--staged] FILE...
# --staged checks the index copy, so a partially staged file can't slip past.
set -euo pipefail

staged=false
if [[ "${1:-}" == "--staged" ]]; then
  staged=true
  shift
fi

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

failed=0
for file in "$@"; do
  # sops picks its parser from the extension, so keep the basename.
  copy="$file"
  if $staged; then
    copy="$scratch/$(basename "$file")"
    git show ":$file" > "$copy"
  fi

  if [[ "$file" == *.sops.yaml ]]; then
    if ! sops filestatus "$copy" | grep -q '"encrypted":true'; then
      echo "not encrypted: $file" >&2
      failed=1
    fi
  elif grep -Eq '^kind:[[:space:]]*["'\'']?Secret["'\'']?[[:space:]]*$' "$copy"; then
    echo "Secret outside a *.sops.yaml file: $file" >&2
    failed=1
  fi
done

exit "$failed"
