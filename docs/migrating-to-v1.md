# Migrate to v1

The pre-v1 revision `3664557b5113a099b8990e4b296f58c40343c64f` was intentionally unstable. Migrate custom jobs as one change:

1. Add a pinned `actions/checkout` step with `persist-credentials: false`.
2. Replace `rust-job-setup` with `actions/setup-rust`.
3. Rename the `base` dependency profile to `build`.
4. Rename each `sccache-` input prefix to `compiler-cache-`.
5. Replace `resource-report` with `actions/report-resources`.
6. Replace `workflow-validation.yml` with `validate-workflows.yml` and pass `runner-json` explicitly.

Reusable workflows were renamed as follows:

| Pre-v1 | v1 |
| --- | --- |
| `rust-check.yml` | `rust-quality.yml` |
| `cargo-flux-check.yml` | `cargo-flux-quality.yml` |
| `rust-native.yml` | `rust-native-build.yml` |
| `workflow-validation.yml` | `validate-workflows.yml` |

Replace the pre-v1 revision with the full `v1.0.0` commit SHA only after the release tag exists.
