#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly auth=${1:-}

AUTH=$auth bash "$script_dir/validate-single-line-env.sh" \
  AUTH ENDPOINT BUCKET ACCESS_KEY SECRET_KEY SESSION_TOKEN USE_SSL GITHUB_WORKSPACE

case "$auth" in
  static|ambient|anonymous) ;;
  *)
    echo 'Cannot render an unresolved compiler-cache authentication mode.' >&2
    exit 1
    ;;
esac

if [[ "$auth" == anonymous && (-n "${AWS_ACCESS_KEY_ID:-}" || -n "${AWS_SECRET_ACCESS_KEY:-}") ]]; then
  echo 'Anonymous compiler-cache access requires an environment without inherited static AWS credentials.' >&2
  exit 1
fi

printf '%s\n' \
  'RUSTC_WRAPPER=sccache' \
  "SCCACHE_BUCKET=${BUCKET:-}" \
  "SCCACHE_ENDPOINT=${ENDPOINT:-}" \
  'SCCACHE_REGION=auto' \
  "SCCACHE_S3_USE_SSL=${USE_SSL:-}" \
  'SCCACHE_S3_KEY_PREFIX=rust/v1' \
  "SCCACHE_BASEDIRS=${GITHUB_WORKSPACE:-}"

case "$auth" in
  static)
    printf '%s\n' \
      "AWS_ACCESS_KEY_ID=${ACCESS_KEY:-}" \
      "AWS_SECRET_ACCESS_KEY=${SECRET_KEY:-}" \
      "AWS_SESSION_TOKEN=${SESSION_TOKEN:-}" \
      'SCCACHE_S3_NO_CREDENTIALS=false' \
      'SCCACHE_S3_RW_MODE=READ_WRITE'
    ;;
  ambient)
    printf '%s\n' \
      'SCCACHE_S3_NO_CREDENTIALS=false' \
      'SCCACHE_S3_RW_MODE=READ_WRITE'
    ;;
  anonymous)
    printf '%s\n' \
      'SCCACHE_S3_NO_CREDENTIALS=true' \
      'SCCACHE_S3_RW_MODE=READ_ONLY'
    ;;
esac
