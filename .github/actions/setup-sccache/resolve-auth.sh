#!/usr/bin/env bash
set -euo pipefail

readonly auth=${1:-}
readonly endpoint_present=${2:-}
readonly bucket_present=${3:-}
readonly access_key_present=${4:-}
readonly secret_key_present=${5:-}
readonly session_token_present=${6:-}
readonly inherited_access_key_present=${7:-}
readonly inherited_secret_key_present=${8:-}

for present in "$endpoint_present" "$bucket_present" "$access_key_present" \
  "$secret_key_present" "$session_token_present" "$inherited_access_key_present" \
  "$inherited_secret_key_present"; do
  case "$present" in
    true|false) ;;
    *)
      echo 'Compiler-cache resolver received an invalid presence flag.' >&2
      exit 1
      ;;
  esac
done

case "$auth" in
  static)
    if [[ "$endpoint_present/$bucket_present/$access_key_present/$secret_key_present/$session_token_present" == \
      false/false/false/false/false ]]; then
      printf 'enabled=false\nauth=disabled\n'
    elif [[ "$endpoint_present/$bucket_present/$access_key_present/$secret_key_present" == \
      true/true/true/true ]]; then
      printf 'enabled=true\nauth=static\n'
    else
      echo 'Static compiler-cache authentication requires endpoint, bucket, access key, and secret key; the session token is optional.' >&2
      exit 1
    fi
    ;;
  ambient)
    if [[ "$endpoint_present/$bucket_present/$access_key_present/$secret_key_present/$session_token_present" != \
      true/true/false/false/false ]]; then
      echo 'Ambient compiler-cache authentication requires endpoint and bucket without explicit credentials.' >&2
      exit 1
    fi
    printf 'enabled=true\nauth=ambient\n'
    ;;
  anonymous)
    if [[ "$endpoint_present/$bucket_present/$access_key_present/$secret_key_present/$session_token_present" != \
      true/true/false/false/false ]]; then
      echo 'Anonymous compiler-cache access requires endpoint and bucket without credentials.' >&2
      exit 1
    fi
    if [[ "$inherited_access_key_present/$inherited_secret_key_present" != false/false ]]; then
      echo 'Anonymous compiler-cache access requires an environment without inherited static AWS credentials.' >&2
      exit 1
    fi
    printf 'enabled=true\nauth=anonymous\n'
    ;;
  *)
    echo 'Compiler-cache authentication must be static, ambient, or anonymous.' >&2
    exit 1
    ;;
esac
