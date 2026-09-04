# pulse-actions

Reusable, read-only Rust CI for Pulse repositories.

The repository exports three reusable workflows and three composite actions:

- `rust-check.yml` runs `fmt`, `clippy`, and tests on the public Linux runner pool.
- `cargo-flux-check.yml` runs a fixed list of Cargo Flux tasks on the public Linux runner pool.
- `rust-native.yml` builds one binary package on Linux, macOS, and Windows.
- `setup-rust` installs a pinned toolchain and restores the platform cache.
- `setup-sccache` sends compiler outputs to a caller-configured S3-compatible cache.
- `resource-report` writes runner CPU, memory, and storage data to the job summary.

Callers pin a full commit SHA. Release, publishing, signing, and other privileged jobs stay in the calling repository.

```yaml
permissions:
  contents: read

jobs:
  check:
    uses: ignition-is-go/pulse-actions/.github/workflows/rust-check.yml@0123456789abcdef0123456789abcdef01234567
    secrets: inherit
```

Configure `CI_CACHE_ENDPOINT`, `CI_CACHE_BUCKET`, `CI_CACHE_ACCESS_KEY`, and `CI_CACHE_SECRET_KEY` as caller-repository secrets. Jobs without the complete configuration, including fork pull requests, run normally with remote compiler caching disabled.

See [the design](docs/design.md) for the contract and security boundary.
