# Design

`pulse-actions` owns deterministic, unprivileged Rust CI setup and common job shapes. Calling repositories own scheduling and policy.

The public layer contains complete actions and reusable workflows. Implementation actions live under `.github/actions` and cannot be called as public entry points. Reusable workflows accept runner JSON instead of naming infrastructure. They do not accept executable command strings.

`actions/setup-rust` validates its dependency profile and compiler-cache configuration at the input boundary. Linux dependencies are closed profiles rather than arbitrary package strings. Compiler-cache configuration resolves to disabled, static credentials, ambient credentials, or anonymous read-only access. Mixed credential modes and multiline environment values fail before installation. The endpoint scheme controls TLS.

Static authentication preserves the v1.0 input contract and supports an optional session token. Ambient authentication leaves the runner's AWS credential provider chain untouched. Both modes explicitly select read/write cache access. Anonymous authentication requires a clean static-credential environment and is always read-only. Direct action callers own credential acquisition and identity permissions. Reusable workflows do not acquire OIDC credentials.

Every workflow grants only `contents: read`. The repository contains no runner identities, network addresses, bucket names, or credentials. It does not use `pull_request_target`, publish, sign, deploy, or perform privileged release work. Calling repositories use exact protected tags for public Pulse Actions entry points, pin third-party actions to full commit SHAs, and explicitly map each optional cache secret.
