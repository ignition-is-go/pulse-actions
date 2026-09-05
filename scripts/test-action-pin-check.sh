#!/usr/bin/env bash
set -euo pipefail

readonly checker="$PWD/.github/actions/validate-workflows/check-action-pins.sh"
fixture=$(mktemp -d "${RUNNER_TEMP:-/tmp}/pulse-actions-pin-test.XXXXXX")
readonly fixture
trap 'rm -rf "$fixture"' EXIT

git -C "$fixture" init -q

write_fixture() {
  local path=$1
  local uses=$2

  mkdir -p "$(dirname "$fixture/$path")"
  if [[ "$path" == .github/workflows/* ]]; then
    printf '%s\n' \
      'name: Pin fixture' \
      'on: push' \
      'jobs:' \
      '  check:' \
      '    runs-on: ubuntu-24.04' \
      '    steps:' \
      "      - uses: $uses" \
      > "$fixture/$path"
  else
    printf '%s\n' \
      'runs:' \
      '  using: composite' \
      '  steps:' \
      "    - uses: $uses" \
      > "$fixture/$path"
  fi
  git -C "$fixture" add "$path"
}

assert_reference() {
  local expectation=$1
  local path=$2
  local reference=$3
  local output

  rm -rf "$fixture/exported" "$fixture/.github"
  git -C "$fixture" read-tree --empty
  write_fixture "$path" "$reference"
  if output=$(cd "$fixture" && "$checker" 2>&1); then
    if [[ "$expectation" == reject ]]; then
      printf 'accepted invalid reference in %s: %s\n' "$path" "$reference" >&2
      exit 1
    fi
  elif [[ "$expectation" == accept ]]; then
    printf 'rejected valid reference in %s: %s\n%s\n' "$path" "$reference" "$output" >&2
    exit 1
  elif [[ "$output" != *"$path:"* ]]; then
    printf 'diagnostic omitted the source path for %s: %s\n' "$reference" "$output" >&2
    exit 1
  fi
}

assert_document() {
  local expectation=$1
  local path=$2
  local document=$3
  local output

  rm -rf "$fixture/exported" "$fixture/.github"
  git -C "$fixture" read-tree --empty
  mkdir -p "$(dirname "$fixture/$path")"
  printf '%s\n' "$document" > "$fixture/$path"
  git -C "$fixture" add "$path"

  if output=$(cd "$fixture" && "$checker" 2>&1); then
    if [[ "$expectation" == reject ]]; then
      printf 'accepted invalid document in %s:\n%s\n' "$path" "$document" >&2
      exit 1
    fi
  elif [[ "$expectation" == accept ]]; then
    printf 'rejected valid document in %s:\n%s\n%s\n' "$path" "$document" "$output" >&2
    exit 1
  elif [[ "$output" != *"$path:"* ]]; then
    printf 'diagnostic omitted the source path: %s\n' "$output" >&2
    exit 1
  fi
}

readonly sha=0123456789abcdef0123456789abcdef01234567
readonly digest=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef

cases=(
  "accept|actions/checkout@$sha"
  "accept|\"actions/checkout@$sha\" # v6.1.0"
  "accept|'actions/checkout@$sha' # v6.1.0"
  'accept|./actions/local'
  'accept|$/.github/actions/local'
  "accept|docker://example/image@sha256:$digest"
  'reject|actions/checkout@main'
  'reject|actions/checkout@v6'
  "reject|actions/checkout@\${{ github.ref }}"
  "reject|\"actions/checkout@$sha # inside-value\""
  "reject|'actions/checkout@$sha # inside-value'"
  "reject|\"actions/checkout@$sha\" junk"
  "reject|\"actions/checkout@$sha"
  "reject|actions/checkout@$sha#not-a-comment"
  'reject|lookalike/pulse-actions/actions/setup-rust@v1.1.0'
  'reject|ignition-is-go/other/actions/setup-rust@v1.1.0'
  'reject|ignition-is-go/pulse-actions/.github/actions/setup-sccache@v1.1.0'
  'reject|ignition-is-go/pulse-actions/actions/setup-rust/action.yml@v1.1.0'
  'reject|ignition-is-go/pulse-actions/actions/setup-rust@v1'
  'reject|ignition-is-go/pulse-actions/actions/setup-rust@v1.1'
  'reject|ignition-is-go/pulse-actions/actions/setup-rust@v1.1.0-rc.1'
  'reject|ignition-is-go/pulse-actions/actions/setup-rust@v1.1.0+build'
  'reject|ignition-is-go/pulse-actions/actions/setup-rust@v01.1.0'
  'reject|ignition-is-go/pulse-actions/actions/setup-rust@main'
)

for test_case in "${cases[@]}"; do
  IFS='|' read -r expectation reference <<< "$test_case"
  [[ -n "$expectation" ]] || continue
  assert_reference "$expectation" exported/action.yml "$reference"
  assert_reference "$expectation" .github/workflows/pins.yml "$reference"
done

while IFS= read -r path; do
  reference_path=${path%/action.yml}
  assert_reference accept exported/action.yml "ignition-is-go/pulse-actions/$reference_path@v1.1.0"
  assert_reference accept .github/workflows/pins.yml "\"ignition-is-go/pulse-actions/$reference_path@v1.1.0\" # protected release"
done < contract/public-api.txt

assert_document reject exported/action.yml $'runs:\n  using: composite\n  steps:\n    - { uses: actions/checkout@main }'
assert_document reject exported/action.yml $'runs:\n  using: composite\n  steps: [{ uses: actions/checkout@main }]'
assert_document reject exported/action.yml $'runs:\n  using: composite\n  steps:\n    - "uses": actions/checkout@main'
assert_document reject exported/action.yml $'runs:\n  using: composite\n  steps:\n    - uses : actions/checkout@main'
assert_document reject exported/action.yml $'runs:\n  using: composite\n  steps:\n    - nested: { uses: actions/checkout@main }'
assert_document reject exported/action.yml $'runs:\n  using: composite\n  steps:\n    - uses: [actions/checkout@main]'
assert_document reject exported/action.yml $'runs:\n  using: composite\n  steps:\n    - uses: "actions/checkout@0123456789abcdef0123456789abcdef01234567 # embedded"'

assert_document accept exported/action.yml "runs: { using: composite, steps: [{ uses: actions/checkout@$sha }] }"
assert_document accept exported/action.yml $'runs:\n  using: composite\n  steps:\n    - "uses": ignition-is-go/pulse-actions/actions/setup-rust@v1.1.0 # outside comment'
assert_document reject .github/workflows/pins.yml $'name: Pins\non: push\njobs:\n  check:\n    runs-on: ubuntu-24.04\n    steps: [{ uses: actions/checkout@main }]'
assert_document accept .github/workflows/pins.yml "{ name: Pins, on: push, jobs: { check: { runs-on: ubuntu-24.04, steps: [{ uses: actions/checkout@$sha }] } } }"
