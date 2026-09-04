#!/usr/bin/env bash
set -euo pipefail

readonly private_network='(^|[^0-9])(10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|192\.168\.[0-9]{1,3}\.[0-9]{1,3}|172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3})([^0-9]|$)'
readonly private_hostname='https?://[^/[:space:]]+\.(internal|local)(:[0-9]+)?([/[:space:]]|$)'

status=0
while IFS= read -r -d '' file; do
  if grep -En "$private_network|$private_hostname" "$file"; then
    printf 'private infrastructure reference in %s\n' "$file" >&2
    status=1
  fi
done < <(git ls-files -z)

exit "$status"
