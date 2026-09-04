# Reusable Rust CI

`pulse-actions` owns deterministic, unprivileged CI jobs. Calling repositories own triggers, concurrency, release policy, credentials, and commands that are specific to one product.

## Public contracts

`rust-check.yml` runs the standard Cargo format, Clippy, and test commands. `cargo-flux-check.yml` runs named tasks through a pinned Cargo Flux installation. `rust-native.yml` builds one package for the native Linux, macOS, and Windows targets.

`setup-rust` is the lower-level contract for a caller that needs custom steps. It owns the toolchain action, Rust cache, and optional Windows sparse-index cache. The action reports whether Cargo can run offline after exact cache hits.

The reusable workflows select runner pools. Callers cannot supply raw labels or executable command strings. This keeps the scheduling and cache rules in one reviewed place.

## Security boundary

Every workflow grants only `contents: read`. The workflows accept no secrets and do not use `pull_request_target`. They do not tag, publish, sign, deploy, or call another repository.

The repository is public because both public and private repositories call it. Every caller and every third-party action uses a full commit SHA. Version tags document releases but callers do not trust mutable tags.

## Versioning

An additive input with the same default is backward-compatible. Removing an input, changing a default, changing a runner mapping, or changing cache semantics requires a major release. Release tags are immutable.
