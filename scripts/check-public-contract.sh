#!/usr/bin/env bash
set -euo pipefail

readonly expected=contract/public-api.txt
readonly actual_file="${RUNNER_TEMP:-/tmp}/pulse-actions-public-api.txt"
readonly estate_label='ci-[[:alnum:]_-]+-(ephemeral|persistent)|site-[[:alnum:]_-]+|cpu-ge-[0-9]+|ram-ge-[0-9]+|disk-ge-[0-9]+'

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

if git grep -nE "RUNNER_NAME|$estate_label" -- . ':!scripts/check-public-contract.sh'; then
  echo 'The public repository contains an estate-specific runner identifier.' >&2
  exit 1
fi

for label in "ci-""windows-ephemeral" "site-""example" "cpu-ge-""32" "ram-ge-""64" "disk-ge-""500"; do
  if ! grep -qE "$estate_label" <<< "$label"; then
    echo "The estate-label guard missed its generated fixture: $label" >&2
    exit 1
  fi
done

resolver=.github/actions/setup-sccache/resolve-endpoint.sh
[[ $("$resolver" https://cache.example.invalid) == true ]]
[[ $("$resolver" http://cache.example.invalid) == false ]]
if "$resolver" ftp://cache.example.invalid >/dev/null 2>&1; then
  echo 'The compiler-cache endpoint validator accepted an unsupported scheme.' >&2
  exit 1
fi
