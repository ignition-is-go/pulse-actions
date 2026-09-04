# Reusable Rust CI

`pulse-actions` owns deterministic, unprivileged CI setup and common job shapes. Calling repositories own triggers, concurrency, runner selection, release policy, credentials, and commands that are specific to one product.

## Public contracts

`rust-check.yml` runs the standard Cargo format, Clippy, and test commands. `cargo-flux-check.yml` runs named tasks through a pinned Cargo Flux installation. `rust-native.yml` builds one package for the native Linux, macOS, and Windows targets.

`setup-rust` is the lower-level contract for a caller that needs custom steps. It owns the toolchain action, Rust cache, and optional Windows sparse-index cache. The action reports whether Cargo can run offline after exact cache hits.

`rust-job-setup` is the normal contract for a custom Rust job. It owns secure checkout, initial resource reporting, approved Linux dependency profiles, toolchain setup, and caching. The caller keeps its exact Cargo commands and emits the final resource report after them. This avoids encoding Cargo's command line as another configuration language.

Reusable workflows accept runner JSON because the calling repository owns scheduling. They do not accept executable command strings. Dependency profiles are reviewed allow-lists rather than arbitrary package names.

## Security boundary

Every workflow grants only `contents: read`. Rust workflows accept optional, bucket-scoped compiler-cache secrets and run without remote caching when all four values are absent. They do not use `pull_request_target`, tag, publish, sign, deploy, or call another repository.

The repository is public because both public and private repositories call it. Workflow validation rejects mutable third-party action references. Callers pin a full `pulse-actions` commit SHA.

## Versioning

An additive input with the same default is backward-compatible. Removing an input, changing a default, changing a runner mapping, or changing cache semantics is breaking. The repository currently publishes no version tags, so commit SHAs are the only supported version identifiers.
