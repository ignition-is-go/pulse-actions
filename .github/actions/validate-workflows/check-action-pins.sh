#!/usr/bin/env bash
set -euo pipefail

readonly action_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly repository_root=$(cd -- "$action_dir/../../.." && pwd)
readonly public_api="$repository_root/contract/public-api.txt"

extract_uses_reference() {
  local line=$1
  local value

  [[ "$line" =~ ^[[:space:]-]*uses:[[:space:]]*(.*)$ ]] || return 1
  value=${BASH_REMATCH[1]}

  if [[ "$value" =~ ^([^[:space:]#\'\"]+)([[:space:]]+\#.*)?[[:space:]]*$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$value" =~ ^\'([^\'#]*)\'([[:space:]]+\#.*)?[[:space:]]*$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$value" =~ ^\"([^\"#]*)\"([[:space:]]+\#.*)?[[:space:]]*$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  return 1
}

is_public_pulse_actions_tag() {
  local reference=$1
  local path

  if [[ ! "$reference" =~ ^ignition-is-go/pulse-actions/(.+)@v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    return 1
  fi
  path=${BASH_REMATCH[1]}
  grep -Fxq "$path" "$public_api"
}

reference_is_allowed() {
  local reference=$1

  if [[ "$reference" =~ ^(\./|\$/)[^[:space:]#\'\"@]+$ ]]; then
    return 0
  fi
  if [[ "$reference" =~ ^docker://[^[:space:]@]+@sha256:[0-9a-fA-F]{64}$ ]]; then
    return 0
  fi
  if [[ "$reference" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(/[A-Za-z0-9_.-]+)*@[0-9a-fA-F]{40}$ ]]; then
    return 0
  fi
  is_public_pulse_actions_tag "$reference"
}

status=0
while IFS= read -r -d '' file; do
  while IFS=: read -r line_number line; do
    reference=
    if ! reference=$(extract_uses_reference "$line") || ! reference_is_allowed "$reference"; then
      printf '%s:%s: mutable or invalid uses reference: %s\n' \
        "$file" "$line_number" "${reference:-$line}" >&2
      status=1
    fi
  done < <(grep -nE '^[[:space:]-]*uses:[[:space:]]*' "$file" || true)
done < <(git ls-files -z | grep -zE '(^|/)action\.ya?ml$|^\.github/workflows/.*\.ya?ml$')

exit "$status"
