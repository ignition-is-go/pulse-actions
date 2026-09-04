#!/usr/bin/env bash
set -euo pipefail

readonly action=setup-rust/action.yml
readonly hash_expression="hashFiles('**/Cargo.lock')"
readonly producer="      run: echo \"hash=\${{ $hash_expression }}\" >> \"\$GITHUB_OUTPUT\""
readonly registry_consumer='        key: ${{ github.repository }}-${{ runner.os }}-${{ runner.arch }}-cargo-registry-${{ inputs.toolchain }}-${{ inputs.cache-shared-key }}-${{ steps.lockfile.outputs.hash }}-v1'
readonly index_consumer="        key: \${{ inputs.windows-sparse-index-key || format('{0}-windows-sparse-index-{1}-{2}-v1', github.repository, inputs.toolchain, steps.lockfile.outputs.hash) }}"

line_of_exactly_one() {
  local value=$1
  local description=$2
  local matches
  matches=$(grep -Fnx "$value" "$action" || true)
  if [[ $(wc -l <<< "$matches") -ne 1 || -z "$matches" ]]; then
    echo "$description must occur exactly once." >&2
    exit 1
  fi
  cut -d: -f1 <<< "$matches"
}

if [[ $(grep -Fc "$hash_expression" "$action") -ne 1 ]]; then
  echo 'Cargo.lock must be hashed exactly once.' >&2
  exit 1
fi

producer_line=$(line_of_exactly_one "$producer" 'The pre-build lockfile hash producer')
registry_line=$(line_of_exactly_one "$registry_consumer" 'The registry cache key consumer')
index_line=$(line_of_exactly_one "$index_consumer" 'The sparse-index cache key consumer')

if (( producer_line >= registry_line || producer_line >= index_line )); then
  echo 'The lockfile hash must be captured before both cache keys are initialized.' >&2
  exit 1
fi
