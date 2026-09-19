# pulse-actions

Reusable, read-only Rust CI building blocks.

The v1 contract exports two composite actions and four reusable workflows:

- `actions/setup-rust` installs Rust, optional Linux build dependencies, and Cargo caches.
- `actions/report-resources` records CPU, memory, storage, and compiler-cache statistics without exposing runner identity.
- `rust-quality.yml` runs formatting, Clippy, and tests.
- `cargo-flux-quality.yml` runs a caller-selected list of Cargo Flux tasks.
- `rust-native-build.yml` builds one package for native Linux, macOS, and Windows targets.
- `validate-workflows.yml` checks workflow syntax, embedded shell, and immutable action references.

Callers own triggers, concurrency, runner selection, release policy, and product-specific commands. Use an exact protected semantic-version tag for a public Pulse Actions entry point. Pin every third-party action to a full commit SHA:

```yaml
permissions:
  contents: read

jobs:
  check:
    uses: ignition-is-go/pulse-actions/.github/workflows/rust-quality.yml@v1.1.0
    with:
      runner-json: '"ubuntu-24.04"'
    secrets:
      CI_CACHE_ENDPOINT: ${{ secrets.CI_CACHE_ENDPOINT }}
      CI_CACHE_BUCKET: ${{ secrets.CI_CACHE_BUCKET }}
      CI_CACHE_ACCESS_KEY: ${{ secrets.CI_CACHE_ACCESS_KEY }}
      CI_CACHE_SECRET_KEY: ${{ secrets.CI_CACHE_SECRET_KEY }}
```

Custom jobs compose the actions directly:

```yaml
steps:
  - uses: actions/checkout@d23441a48e516b6c34aea4fa41551a30e30af803 # v6.1.0
    with:
      persist-credentials: false
  - uses: ignition-is-go/pulse-actions/actions/setup-rust@v1.1.0
    with:
      components: rustfmt,clippy
      linux-dependencies: build
      compiler-cache-endpoint: ${{ secrets.CI_CACHE_ENDPOINT }}
      compiler-cache-bucket: ${{ secrets.CI_CACHE_BUCKET }}
      compiler-cache-access-key: ${{ secrets.CI_CACHE_ACCESS_KEY }}
      compiler-cache-secret-key: ${{ secrets.CI_CACHE_SECRET_KEY }}
  - run: cargo test --workspace
  - uses: ignition-is-go/pulse-actions/actions/report-resources@v1.1.0
    if: always()
```

Remote compiler caching supports three authentication modes. `static` is the default and preserves v1.0 behavior. A completely empty static configuration disables the remote cache, including on fork pull requests.

| `compiler-cache-auth` | Required values | Credential source | Access |
| --- | --- | --- | --- |
| `static` | endpoint, bucket, access key, secret key | action inputs; session token optional | read/write |
| `ambient` | endpoint, bucket | runner environment, AWS profile, IMDS, or web identity | provider policy |
| `anonymous` | endpoint, bucket | none | read-only |

Reusable workflows accept endpoint and bucket as non-secret inputs or through the legacy `CI_CACHE_ENDPOINT` and `CI_CACHE_BUCKET` secrets. A nonempty input takes precedence over its matching secret. This lets fork pull requests use an anonymous cache without receiving secrets.

Reusable workflows forward explicit credentials only in static mode. Ambient and anonymous modes receive empty explicit credential inputs even when the caller uses `secrets: inherit`. Anonymous mode requires a clean environment without `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY`, and fails before installation if either is inherited. The endpoint scheme selects encrypted (`https`) or unencrypted (`http`) transport. Direct `setup-rust` callers may establish credentials first and grant the required permissions themselves. Reusable workflows only use credentials already present on the runner and do not acquire OIDC credentials. Pulse Actions does not request identity permissions or accept executable commands.

`rust-native-build.yml` callers can set `macos-x64: false` when they support Apple Silicon macOS only. The default remains `true` for existing callers.

See [the public contract](docs/contract.md), [v1 migration guide](docs/migrating-to-v1.md), [design](docs/design.md), and [release policy](docs/releases.md).

## Build-directory caching on S3

Set `cache-target-backend: s3` on `actions/setup-rust` or a Rust reusable workflow to store build directories alongside the compiler cache. Use the same `compiler-cache-*` endpoint, bucket, and credentials shown above. This option requires static authentication and Node.js 20 or later on the runner's PATH.

```yaml
with:
  cache-target-backend: s3
  cache-zstd-level: "3"
  compiler-cache-endpoint: ${{ secrets.CI_CACHE_ENDPOINT }}
  compiler-cache-bucket: ${{ secrets.CI_CACHE_BUCKET }}
  compiler-cache-access-key: ${{ secrets.CI_CACHE_ACCESS_KEY }}
  compiler-cache-secret-key: ${{ secrets.CI_CACHE_SECRET_KEY }}
```

For reusable workflows, set `cache-target-backend` under `with` and pass the four `CI_CACHE_*` secrets under `secrets`, as in the first example. Keep compiler caching enabled on each native-build platform that uses S3 target caching.

The action resolves target and build directories with `cargo metadata`, including custom Cargo configuration. `cache-workspaces` also accepts explicit mappings such as `. -> target` or `crates/service -> output`. An explicit mapping caches only the named directory. `cache-targets: 'false'` disables build-directory caching for either backend.

S3 target archives retain zstd's level 3 default. Set `cache-zstd-level` from 1 through 19 when storage or network constraints justify a different tradeoff. Fast LAN caches may benefit from level 1 because it spends less time compressing a larger archive.

Linux and macOS archives use `rust/v1/targets/`, covered by existing `rust/v1/*` compiler-cache permissions and retention rules. Windows retains `rust-target-v1-` because the pinned provider uses platform-specific path separators for S3 object names. Unix caches saved under the old prefix will miss once and populate the new namespace. Cache keys include the repository, branch, actual compiler version, operating system, architecture, dependency lockfile, build settings, workspace paths, and checked-out commit. A miss can restore an older archive from the same ref, the PR base branch, or the default branch, in that order. Archives retain workspace crates as well as dependencies. Cargo still checks whether restored artifacts are reusable. Successful jobs save new archives. Same-repository pull requests save under their own pull-request ref, so later commits can reuse their outputs without making them available to branch builds or other pull requests. Fork pull requests and pull_request_target jobs only restore. The credentials need `s3:ListBucket` for this prefix and `s3:GetObject`/`s3:PutObject` for its objects. Set a bucket lifecycle rule on this prefix to expire old archives.

Large target archives use multipart uploads. The archive provider also requires `s3:GetBucketLocation`, `s3:ListBucketMultipartUploads`, and `s3:ListMultipartUploadParts`; successful compiler-cache writes do not prove these permissions are available. [The additional target-cache policy](docs/target-cache-policy.json) includes all six required actions. If your existing policy already grants these operations under `rust/v1/*`, Linux and macOS need no policy change. Otherwise, replace `example-ci-cache` with your bucket name and add the missing permissions. Windows still needs the flat-prefix permissions. Do not replace the compiler-cache permissions with this archive-only policy. See the [pinned provider's permission requirements](https://github.com/tespkg/actions-cache/tree/e07e2d4953dc8c020d447363e5064e36d04f3cf9#amazon-s3-permissions).

Cargo registry downloads and the optional Windows sparse-index cache still use GitHub storage. S3 archive failures appear in job logs and do not fall back to GitHub. Missing credentials fail setup when S3 target caching is explicitly selected. The default backend remains `github`.

Run `node --test scripts/test-target-cache.cjs` for configuration tests. Run `uv run scripts/test-s3-target-cache.py` to build a Rust fixture and verify its archive round trip against a local S3 test server, without LAN credentials.
