#!/usr/bin/env bash
set -euo pipefail

readonly validator="$PWD/.github/actions/validate-workflows"
readonly fixture="${RUNNER_TEMP:-/tmp}/pulse-actions-validation-test"

rm -rf "$fixture"
mkdir -p "$fixture/.github/workflows"
git -C "$fixture" init -q
printf '%s\n' \
  'name: Self reference' \
  'on: push' \
  'jobs:' \
  '  check:' \
  '    runs-on: ubuntu-24.04' \
  '    steps:' \
  '      - uses: $/actions/example' \
  > "$fixture/.github/workflows/self-reference.yml"
git -C "$fixture" add .github/workflows/self-reference.yml

(cd "$fixture" && \
  RUNNER_TEMP="${RUNNER_TEMP:-/tmp}" \
  GITHUB_WORKSPACE="$fixture" \
  GITHUB_ACTION_PATH="$validator" \
  "$validator/check.sh")
