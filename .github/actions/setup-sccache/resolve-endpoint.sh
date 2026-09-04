#!/usr/bin/env bash
set -euo pipefail

case "${1:-}" in
  https://*) printf 'true\n' ;;
  http://*) printf 'false\n' ;;
  *)
    echo 'Compiler-cache endpoint must use http:// or https://.' >&2
    exit 1
    ;;
esac
