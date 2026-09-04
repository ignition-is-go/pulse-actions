#!/usr/bin/env bash
set -euo pipefail

status=0
while IFS= read -r -d '' file; do
  while IFS=: read -r line_number line; do
    reference=$(sed -E 's/^[[:space:]-]*uses:[[:space:]]*//' <<< "$line")
    reference=${reference%%[[:space:]]#*}
    reference=${reference#\"}
    reference=${reference%\"}
    reference=${reference#\'}
    reference=${reference%\'}

    case "$reference" in
      ./*|\$/*) continue ;;
    esac
    if [[ "$reference" =~ ^docker://[^[:space:]@]+@sha256:[0-9a-fA-F]{64}$ ]]; then
      continue
    fi
    if [[ "$reference" =~ ^[^/[:space:]]+/[^@[:space:]]+@[0-9a-fA-F]{40}$ ]]; then
      continue
    fi

    printf '%s:%s: mutable or invalid uses reference: %s\n' \
      "$file" "$line_number" "$reference" >&2
    status=1
  done < <(grep -nE '^[[:space:]-]*uses:[[:space:]]*' "$file" || true)
done < <(
  find . -type f \
    \( -path './.github/workflows/*.yml' -o -path './.github/workflows/*.yaml' \
       -o -path './.github/actions/*/action.yml' -o -path './.github/actions/*/action.yaml' \
       -o -path './action.yml' -o -path './action.yaml' \) \
    -print0
)

exit "$status"
