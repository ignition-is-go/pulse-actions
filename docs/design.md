# Design

`pulse-actions` owns deterministic, unprivileged Rust CI setup and common job shapes. Calling repositories own scheduling and policy.

The public layer contains complete actions and reusable workflows. Private implementation actions live under `.github/actions` and may change without notice. Reusable workflows accept runner JSON instead of naming infrastructure. They do not accept executable command strings.

`actions/setup-rust` validates its dependency profile and compiler-cache configuration at the input boundary. Linux dependencies are closed profiles rather than arbitrary package strings. Compiler caching is enabled only when the endpoint, bucket, access key, and secret key are all present. The endpoint scheme controls TLS.

Every workflow grants only `contents: read`. The repository contains no runner identities, network addresses, bucket names, or credentials. It does not use `pull_request_target`, publish, sign, deploy, or perform privileged release work. Calling repositories pin a full commit SHA and explicitly map each optional cache secret.
