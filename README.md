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

See [the public contract](docs/contract.md), [v1 migration guide](docs/migrating-to-v1.md), [design](docs/design.md), and [release policy](docs/releases.md).
