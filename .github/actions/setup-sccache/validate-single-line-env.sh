#!/usr/bin/env bash
set -euo pipefail

for name in "$@"; do
  if [[ ! "$name" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
    echo 'Compiler-cache validator received an invalid environment variable name.' >&2
    exit 1
  fi
  value=${!name-}
  if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
    echo 'Compiler-cache inputs must be single-line values.' >&2
    exit 1
  fi
done
