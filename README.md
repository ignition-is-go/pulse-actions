# pulse-actions

Reusable, read-only Rust CI building blocks.

The v1 contract exports two composite actions and four reusable workflows:

- `actions/setup-rust` installs Rust, optional Linux build dependencies, and Cargo caches.
- `actions/report-resources` records CPU, memory, storage, and compiler-cache statistics without exposing runner identity.
- `rust-quality.yml` runs formatting, Clippy, and tests.
- `cargo-flux-quality.yml` runs a caller-selected list of Cargo Flux tasks.
- `rust-native-build.yml` builds one package for native Linux, macOS, and Windows targets.
- `validate-workflows.yml` checks workflow syntax, embedded shell, and immutable action references.

Callers own triggers, concurrency, runner selection, release policy, and product-specific commands. Pin every reference to a full commit SHA and keep the release tag in a comment for update discovery:

```yaml
permissions:
  contents: read

jobs:
  check:
    uses: ignition-is-go/pulse-actions/.github/workflows/rust-quality.yml@0123456789abcdef0123456789abcdef01234567 # v1.0.0
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
  - uses: ignition-is-go/pulse-actions/actions/setup-rust@0123456789abcdef0123456789abcdef01234567 # v1.0.0
    with:
      components: rustfmt,clippy
      linux-dependencies: build
      compiler-cache-endpoint: ${{ secrets.CI_CACHE_ENDPOINT }}
      compiler-cache-bucket: ${{ secrets.CI_CACHE_BUCKET }}
      compiler-cache-access-key: ${{ secrets.CI_CACHE_ACCESS_KEY }}
      compiler-cache-secret-key: ${{ secrets.CI_CACHE_SECRET_KEY }}
  - run: cargo test --workspace
  - uses: ignition-is-go/pulse-actions/actions/report-resources@0123456789abcdef0123456789abcdef01234567 # v1.0.0
    if: always()
```

All four compiler-cache values must be provided together. If they are absent, including on fork pull requests, the build runs without remote compiler caching. The endpoint scheme selects encrypted (`https`) or unencrypted (`http`) transport.

See [the public contract](docs/contract.md), [v1 migration guide](docs/migrating-to-v1.md), [design](docs/design.md), and [release policy](docs/releases.md).
