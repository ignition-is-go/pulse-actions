#!/usr/bin/env bash
set -euo pipefail

readonly resolver=.github/actions/setup-sccache/resolve-auth.sh
readonly validator=.github/actions/setup-sccache/validate-single-line-env.sh
readonly renderer=.github/actions/setup-sccache/render-env.sh

assert_resolves() {
  local expected=$1
  shift
  local actual
  actual=$(bash "$resolver" "$@")
  [[ "$actual" == "$expected" ]] || {
    printf 'expected %q, got %q\n' "$expected" "$actual" >&2
    exit 1
  }
}

assert_rejects() {
  if bash "$resolver" "$@" >/dev/null 2>&1; then
    printf 'resolver accepted invalid inputs: %s\n' "$*" >&2
    exit 1
  fi
}

for auth in static ambient anonymous; do
  for ((mask = 0; mask < 32; mask++)); do
    flags=()
    for bit in 4 3 2 1 0; do
      if ((mask & (1 << bit))); then flags+=(true); else flags+=(false); fi
    done
    for ((inherited = 0; inherited < 4; inherited++)); do
      inherited_flags=()
      for bit in 1 0; do
        if ((inherited & (1 << bit))); then inherited_flags+=(true); else inherited_flags+=(false); fi
      done
      case "$auth/$mask/$inherited" in
        static/0/*) assert_resolves $'enabled=false\nauth=disabled' "$auth" "${flags[@]}" "${inherited_flags[@]}" ;;
        static/30/*|static/31/*) assert_resolves $'enabled=true\nauth=static' "$auth" "${flags[@]}" "${inherited_flags[@]}" ;;
        ambient/24/*) assert_resolves $'enabled=true\nauth=ambient' "$auth" "${flags[@]}" "${inherited_flags[@]}" ;;
        anonymous/24/0) assert_resolves $'enabled=true\nauth=anonymous' "$auth" "${flags[@]}" "${inherited_flags[@]}" ;;
        *) assert_rejects "$auth" "${flags[@]}" "${inherited_flags[@]}" ;;
      esac
    done
  done
done

assert_rejects unknown true true false false false false false
assert_rejects static yes true true true false false false

AUTH=static ENDPOINT=https://cache.example.invalid BUCKET=cache \
  ACCESS_KEY=access SECRET_KEY=secret SESSION_TOKEN='' \
  bash "$validator" AUTH ENDPOINT BUCKET ACCESS_KEY SECRET_KEY SESSION_TOKEN

secret_with_newline=$'not-printed\nAWS_ACCESS_KEY_ID=injected'
validation_output=$(mktemp)
trap 'rm -f "$validation_output"' EXIT
if SECRET_KEY="$secret_with_newline" bash "$validator" SECRET_KEY >"$validation_output" 2>&1; then
  echo 'single-line validator accepted a newline.' >&2
  exit 1
fi
if grep -q 'not-printed\|injected' "$validation_output"; then
  echo 'single-line validator printed a rejected secret.' >&2
  exit 1
fi
for workflow in \
  .github/workflows/cargo-flux-quality.yml \
  .github/workflows/rust-native-build.yml \
  .github/workflows/rust-quality.yml; do
  grep -q 'compiler-cache-auth:' "$workflow"
  grep -q 'compiler-cache-endpoint:' "$workflow"
  grep -q 'inputs.compiler-cache-endpoint || secrets.CI_CACHE_ENDPOINT' "$workflow"
  grep -q 'inputs.compiler-cache-bucket || secrets.CI_CACHE_BUCKET' "$workflow"
  grep -q 'CI_CACHE_SESSION_TOKEN:' "$workflow"
  grep -q 'compiler-cache-session-token:' "$workflow"
done

for workflow in \
  .github/workflows/cargo-flux-quality.yml \
  .github/workflows/rust-quality.yml; do
  grep -Fq "compiler-cache-access-key: \${{ inputs.compiler-cache-auth == 'static' && secrets.CI_CACHE_ACCESS_KEY || '' }}" "$workflow"
  grep -Fq "compiler-cache-secret-key: \${{ inputs.compiler-cache-auth == 'static' && secrets.CI_CACHE_SECRET_KEY || '' }}" "$workflow"
  grep -Fq "compiler-cache-session-token: \${{ inputs.compiler-cache-auth == 'static' && secrets.CI_CACHE_SESSION_TOKEN || '' }}" "$workflow"
done

grep -Fq "compiler-cache-access-key: \${{ matrix.compiler-cache && inputs.compiler-cache-auth == 'static' && secrets.CI_CACHE_ACCESS_KEY || '' }}" \
  .github/workflows/rust-native-build.yml
grep -Fq "compiler-cache-secret-key: \${{ matrix.compiler-cache && inputs.compiler-cache-auth == 'static' && secrets.CI_CACHE_SECRET_KEY || '' }}" \
  .github/workflows/rust-native-build.yml
grep -Fq "compiler-cache-session-token: \${{ matrix.compiler-cache && inputs.compiler-cache-auth == 'static' && secrets.CI_CACHE_SESSION_TOKEN || '' }}" \
  .github/workflows/rust-native-build.yml
grep -Fq "AUTH: \${{ inputs.compiler-cache-auth }}" .github/workflows/rust-native-build.yml
grep -Fq 'static|ambient|anonymous)' .github/workflows/rust-native-build.yml
grep -Fq 'matrix.compiler-cache == false && matrix.disabled-compiler-cache-auth || inputs.compiler-cache-auth' \
  .github/workflows/rust-native-build.yml

readonly common_env=$'RUSTC_WRAPPER=sccache\nSCCACHE_BUCKET=cache\nSCCACHE_ENDPOINT=https://cache.example.invalid\nSCCACHE_REGION=auto\nSCCACHE_S3_USE_SSL=true\nSCCACHE_S3_KEY_PREFIX=rust/v1\nSCCACHE_BASEDIRS=/workspace'

render() {
  env \
    -u AWS_ACCESS_KEY_ID \
    -u AWS_SECRET_ACCESS_KEY \
    -u AWS_SESSION_TOKEN \
    AUTH=unused \
    ENDPOINT=https://cache.example.invalid \
    BUCKET=cache \
    ACCESS_KEY=access \
    SECRET_KEY=secret \
    SESSION_TOKEN="${SESSION_TOKEN_UNDER_TEST:-}" \
    USE_SSL=true \
    GITHUB_WORKSPACE=/workspace \
    SCCACHE_S3_NO_CREDENTIALS=stale \
    SCCACHE_S3_RW_MODE=STALE \
    bash "$renderer" "$1"
}

assert_rendered() {
  local expected=$1
  local auth=$2
  local actual
  actual=$(render "$auth")
  [[ "$actual" == "$expected" ]] || {
    printf 'unexpected %s environment:\n%s\n' "$auth" "$actual" >&2
    exit 1
  }
}

assert_rendered "$common_env"$'\nAWS_ACCESS_KEY_ID=access\nAWS_SECRET_ACCESS_KEY=secret\nAWS_SESSION_TOKEN=\nSCCACHE_S3_NO_CREDENTIALS=false\nSCCACHE_S3_RW_MODE=READ_WRITE' static
SESSION_TOKEN_UNDER_TEST=token assert_rendered "$common_env"$'\nAWS_ACCESS_KEY_ID=access\nAWS_SECRET_ACCESS_KEY=secret\nAWS_SESSION_TOKEN=token\nSCCACHE_S3_NO_CREDENTIALS=false\nSCCACHE_S3_RW_MODE=READ_WRITE' static
assert_rendered "$common_env"$'\nSCCACHE_S3_NO_CREDENTIALS=false\nSCCACHE_S3_RW_MODE=READ_WRITE' ambient
assert_rendered "$common_env"$'\nSCCACHE_S3_NO_CREDENTIALS=true\nSCCACHE_S3_RW_MODE=READ_ONLY' anonymous

ambient_with_credentials=$(AWS_ACCESS_KEY_ID=inherited AWS_SECRET_ACCESS_KEY=inherited \
  ENDPOINT=https://cache.example.invalid BUCKET=cache USE_SSL=true GITHUB_WORKSPACE=/workspace \
  bash "$renderer" ambient)
if grep -q '^AWS_' <<< "$ambient_with_credentials"; then
  echo 'Ambient mode rendered AWS credential variables.' >&2
  exit 1
fi

if AWS_ACCESS_KEY_ID=inherited ENDPOINT=https://cache.example.invalid BUCKET=cache \
  USE_SSL=true GITHUB_WORKSPACE=/workspace bash "$renderer" anonymous >/dev/null 2>&1; then
  echo 'Anonymous mode accepted inherited static AWS credentials.' >&2
  exit 1
fi

for field in AUTH ENDPOINT BUCKET ACCESS_KEY SECRET_KEY SESSION_TOKEN USE_SSL GITHUB_WORKSPACE; do
  rejected=$'not-printed\r\ninjected'
  if [[ "$field" == AUTH ]]; then
    if ENDPOINT=https://cache.example.invalid BUCKET=cache ACCESS_KEY=access SECRET_KEY=secret \
      USE_SSL=true GITHUB_WORKSPACE=/workspace \
      bash "$renderer" "$rejected" >"$validation_output" 2>&1; then
      printf 'renderer accepted CR/LF in %s.\n' "$field" >&2
      exit 1
    fi
  elif env \
    ENDPOINT=https://cache.example.invalid \
    BUCKET=cache \
    ACCESS_KEY=access \
    SECRET_KEY=secret \
    SESSION_TOKEN=token \
    USE_SSL=true \
    GITHUB_WORKSPACE=/workspace \
    "$field=$rejected" \
    bash "$renderer" static >"$validation_output" 2>&1; then
    printf 'renderer accepted CR/LF in %s.\n' "$field" >&2
    exit 1
  fi
  if grep -q 'not-printed\|injected' "$validation_output"; then
    printf 'renderer printed rejected %s content.\n' "$field" >&2
    exit 1
  fi
done
