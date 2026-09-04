#!/usr/bin/env bash
set -euo pipefail

readonly expected=contract/public-api.txt
readonly actual_file="${RUNNER_TEMP:-/tmp}/pulse-actions-public-api.txt"

{
  git ls-files 'actions/**/action.yml' 'actions/**/action.yaml'
  while IFS= read -r workflow; do
    if grep -qE '^[[:space:]]*workflow_call:' "$workflow"; then
      printf '%s\n' "$workflow"
    fi
  done < <(git ls-files '.github/workflows/*.yml' '.github/workflows/*.yaml')
} | sort > "$actual_file"

if ! diff -u <(sort "$expected") "$actual_file"; then
  echo 'Public entry points differ from contract/public-api.txt.' >&2
  exit 1
fi

sha256sum --check contract/public-api.sha256

if git grep -nE 'RUNNER_NAME|ci-(public|private|trusted|release)|site-\*|cpu-ge-\*|ram-ge-\*|disk-ge-\*' -- . ':!scripts/check-public-contract.sh'; then
  echo 'The public repository contains an estate-specific runner identifier.' >&2
  exit 1
fi

resolver=.github/actions/setup-sccache/resolve-endpoint.sh
[[ $("$resolver" https://cache.example.invalid) == true ]]
[[ $("$resolver" http://cache.example.invalid) == false ]]
if "$resolver" ftp://cache.example.invalid >/dev/null 2>&1; then
  echo 'The compiler-cache endpoint validator accepted an unsupported scheme.' >&2
  exit 1
fi
