#!/usr/bin/env bash
set -euo pipefail

action_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly action_dir
repository_root=$(cd -- "$action_dir/../../.." && pwd)
readonly repository_root
readonly public_api="$repository_root/contract/public-api.txt"
readonly install_dir="${RUNNER_TEMP:-/tmp}/pulse-workflow-validators"
readonly yq="$install_dir/yq"
readonly yq_version=4.53.6
readonly yq_sha256=c5f056448f973ae7d39b5401949648a78f2dc1947d6a8eb65be60d5c504b9385
readonly yq_download="$yq.download.$$"

install_yq() {
  mkdir -p "$install_dir"
  if [[ -f "$yq" ]] && printf '%s  %s\n' "$yq_sha256" "$yq" | sha256sum --check --status; then
    chmod 0755 "$yq"
    return
  fi

  trap 'rm -f "$yq_download"' EXIT
  curl --fail --location --retry 3 --silent --show-error \
    --output "$yq_download" \
    "https://github.com/mikefarah/yq/releases/download/v${yq_version}/yq_linux_amd64"
  printf '%s  %s\n' "$yq_sha256" "$yq_download" | sha256sum --check
  chmod 0755 "$yq_download"
  mv "$yq_download" "$yq"
  trap - EXIT
}

is_public_pulse_actions_tag() {
  local reference=$1
  local path

  if [[ ! "$reference" =~ ^ignition-is-go/pulse-actions/(.+)@v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    return 1
  fi
  path=${BASH_REMATCH[1]}
  grep -Fxq "$path" "$public_api" || grep -Fxq "$path/action.yml" "$public_api"
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

install_yq

readonly query='.. | select(tag == "!!map") | to_entries[] | select(.key == "uses") | [(.value | line), (.value | tag), ((.value | select(tag == "!!str") | @base64) // "")] | @tsv'
status=0
while IFS= read -r -d '' file; do
  if ! records=$("$yq" --unwrapScalar "$query" "$file"); then
    printf '%s: invalid YAML while checking uses references\n' "$file" >&2
    status=1
    continue
  fi
  while IFS=$'\t' read -r line_number value_tag encoded_reference; do
    [[ -n "$line_number" ]] || continue
    if [[ "$value_tag" != '!!str' ]]; then
      printf '%s:%s: uses reference must be a string\n' "$file" "$line_number" >&2
      status=1
      continue
    fi
    reference=$(printf '%s' "$encoded_reference" | base64 --decode)
    if ! reference_is_allowed "$reference"; then
      printf '%s:%s: mutable or invalid uses reference: %s\n' \
        "$file" "$line_number" "$reference" >&2
      status=1
    fi
  done <<< "$records"
done < <(git ls-files -z | grep -zE '(^|/)action\.ya?ml$|^\.github/workflows/.*\.ya?ml$')

exit "$status"
