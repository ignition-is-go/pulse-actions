#!/usr/bin/env bash
set -euo pipefail

if sccache --start-server && sccache --zero-stats; then
  echo 'enabled=true' >>"$GITHUB_OUTPUT"
  exit 0
fi

echo '::warning::Remote compiler cache is unavailable; continuing without sccache.'
sccache --stop-server >/dev/null 2>&1 || true
{
  echo 'RUSTC_WRAPPER='
  echo 'SCCACHE_BUCKET='
  echo 'SCCACHE_ENDPOINT='
  echo 'SCCACHE_REGION='
  echo 'SCCACHE_S3_KEY_PREFIX='
  echo 'SCCACHE_BASEDIRS='
  echo 'SCCACHE_S3_USE_SSL='
  echo 'SCCACHE_S3_NO_CREDENTIALS='
  echo 'SCCACHE_S3_RW_MODE='
  echo 'AWS_ACCESS_KEY_ID='
  echo 'AWS_SECRET_ACCESS_KEY='
  echo 'AWS_SESSION_TOKEN='
} >>"$GITHUB_ENV"
echo 'enabled=false' >>"$GITHUB_OUTPUT"
