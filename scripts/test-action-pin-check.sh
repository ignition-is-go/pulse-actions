#!/usr/bin/env bash
set -euo pipefail

readonly checker="$PWD/.github/actions/validate-workflows/check-action-pins.sh"
readonly fixture="${RUNNER_TEMP:-/tmp}/pulse-actions-pin-test"

rm -rf "$fixture"
mkdir -p "$fixture/exported"
git -C "$fixture" init -q
printf '%s\n' 'runs:' '  using: composite' '  steps:' '    - uses: owner/action@main' > "$fixture/exported/action.yml"
git -C "$fixture" add exported/action.yml

if (cd "$fixture" && "$checker" >/dev/null 2>&1); then
  echo 'The pin checker accepted a mutable reference in an exported action.' >&2
  exit 1
fi

sed -i 's/@main/@0123456789abcdef0123456789abcdef01234567/' "$fixture/exported/action.yml"
(cd "$fixture" && "$checker")
