# pulse-actions

Reusable, read-only Rust CI for Pulse repositories.

The repository exports four reusable workflows and five composite actions:

- `rust-check.yml` runs `fmt`, `clippy`, and tests on the public Linux runner pool.
- `cargo-flux-check.yml` runs a fixed list of Cargo Flux tasks on the public Linux runner pool.
- `rust-native.yml` builds one binary package on Linux, macOS, and Windows.
- `workflow-validation.yml` checks workflow syntax, embedded shell, and runner labels in one Linux job.
- `rust-job-setup` checks out a repository, records its starting resources, installs an approved Linux dependency profile, and configures Rust and caching. It leaves the repository's exact Cargo commands and runner selection in the caller.
- `setup-rust` installs a pinned toolchain and restores the platform cache.
- `setup-sccache` sends compiler outputs to a caller-configured S3-compatible cache.
- `resource-report` writes runner CPU, memory, and storage data to the job summary.
- `validate-workflows` installs pinned validators under the job temporary directory.

Use `rust-job-setup` for repositories whose commands do not exactly match one
of the reusable workflows:

```yaml
jobs:
  check:
    runs-on: ci-public-linux-ephemeral
    steps:
      - uses: ignition-is-go/pulse-actions/rust-job-setup@0123456789abcdef0123456789abcdef01234567
        with:
          components: rustfmt,clippy
          linux-dependencies: base
          sccache-endpoint: ${{ secrets.CI_CACHE_ENDPOINT }}
          sccache-bucket: ${{ secrets.CI_CACHE_BUCKET }}
          sccache-access-key: ${{ secrets.CI_CACHE_ACCESS_KEY }}
          sccache-secret-key: ${{ secrets.CI_CACHE_SECRET_KEY }}
      - run: cargo fmt --all -- --check
      - run: cargo test --workspace
      - uses: ignition-is-go/pulse-actions/resource-report@0123456789abcdef0123456789abcdef01234567
        if: always()
```

Callers pin a full commit SHA. Release, publishing, signing, and other privileged jobs stay in the calling repository.

```yaml
permissions:
  contents: read

jobs:
  check:
    uses: ignition-is-go/pulse-actions/.github/workflows/rust-check.yml@0123456789abcdef0123456789abcdef01234567
    secrets: inherit
```

Configure `CI_CACHE_ENDPOINT`, `CI_CACHE_BUCKET`, `CI_CACHE_ACCESS_KEY`, and `CI_CACHE_SECRET_KEY` as caller-repository secrets. Jobs without the complete configuration, including fork pull requests, run normally with remote compiler caching disabled. Remote `uses:` references in workflows and local composite actions must use a full commit SHA or container digest.

See [the design](docs/design.md) for the contract and security boundary.
