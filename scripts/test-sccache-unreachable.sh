#!/usr/bin/env bash
set -euo pipefail

readonly version=0.17.0
readonly checksum=67c4a96dd237c1f518f6b36083f270f9976d516f1e57fce891755ea782e50006
readonly fixture_dir=$(mktemp -d)
backend_pid=
trap '[[ -z "$backend_pid" ]] || kill "$backend_pid" >/dev/null 2>&1 || true; rm -rf "$fixture_dir"' EXIT

asset="sccache-v${version}-x86_64-unknown-linux-musl.tar.gz"
curl --fail --location --retry 3 --output "$fixture_dir/$asset" \
  "https://github.com/mozilla/sccache/releases/download/v${version}/$asset"
echo "$checksum  $fixture_dir/$asset" | sha256sum --check
tar -xzf "$fixture_dir/$asset" -C "$fixture_dir"
readonly sccache="$fixture_dir/${asset%.tar.gz}/sccache"

printf 'fn main() { println!("uncached fallback"); }\n' >"$fixture_dir/main.rs"
backend_port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
server_port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')

python3 -m http.server "$backend_port" --bind 127.0.0.1 --directory "$fixture_dir" \
  >"$fixture_dir/backend.log" 2>&1 &
backend_pid=$!

cache_env=(env \
  AWS_ACCESS_KEY_ID=synthetic-access \
  AWS_SECRET_ACCESS_KEY=synthetic-secret \
  SCCACHE_BUCKET=unreachable \
  SCCACHE_ENDPOINT="http://127.0.0.1:$backend_port" \
  SCCACHE_REGION=auto \
  SCCACHE_S3_USE_SSL=false \
  SCCACHE_S3_KEY_PREFIX=rust/v1 \
  SCCACHE_IGNORE_SERVER_IO_ERROR=1 \
  SCCACHE_ERROR_LOG="$fixture_dir/sccache.log" \
  SCCACHE_SERVER_PORT="$server_port")

for _ in {1..50}; do
  curl --fail --silent "http://127.0.0.1:$backend_port/" >/dev/null && break
  sleep 0.1
done

"${cache_env[@]}" "$sccache" --start-server
kill "$backend_pid"
wait "$backend_pid" 2>/dev/null || true
backend_pid=

"${cache_env[@]}" "$sccache" rustc "$fixture_dir/main.rs" -o "$fixture_dir/fallback"
"$fixture_dir/fallback" | grep -Fxq 'uncached fallback'
grep -Eiq 'error|failed|connect' "$fixture_dir/sccache.log"

printf 'this is not valid Rust\n' >"$fixture_dir/broken.rs"
if "${cache_env[@]}" "$sccache" rustc "$fixture_dir/broken.rs" -o "$fixture_dir/broken" >/dev/null 2>&1; then
  echo 'sccache hid a compiler failure.' >&2
  exit 1
fi

"${cache_env[@]}" "$sccache" --stop-server >/dev/null 2>&1 || true
