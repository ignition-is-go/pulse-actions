# Changelog

## Unreleased (v1.1.0)

- Add explicit static, ambient, and anonymous compiler-cache authentication modes.
- Support optional session tokens with static credentials.
- Force anonymous compiler-cache access to read-only.
- Let reusable workflows take non-secret cache locations for anonymous fork access.
- Reject mixed credential modes and multiline environment values before installation.
- Require the contract checksum to cover every public entry point and internal action file.

## v1.0.0

- Define two public composite actions and four reusable workflows.
- Require callers to choose runner labels.
- Keep cache configuration optional and validate it as one unit.
- Enforce immutable third-party action references and a leak-free public surface.
- Replace the pre-v1 paths and input names documented in the migration guide.
