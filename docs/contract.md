# Public contract

The authoritative entry-point list is [`contract/public-api.txt`](../contract/public-api.txt). Its checksum snapshot records every path, input, output, default, and transitive implementation file. CI fails if the exported contract changes without an explicit snapshot update.

## Compatibility

The following changes are compatible within v1:

- adding an optional input whose default preserves existing behavior;
- adding an output;
- fixing behavior that contradicts the documented contract;
- updating an internal action without changing exported behavior.

Removing or renaming an entry point, input, secret, or output is breaking. Changing a default, command sequence, cache semantics, or required permission is also breaking.

Runner labels and workflow triggers are deliberately outside this contract. Each calling repository owns them.

## Compiler-cache authentication

The optional `compiler-cache-auth` input accepts `static`, `ambient`, or `anonymous`. Its default is `static`, so v1.0 callers retain their behavior. Static mode requires endpoint, bucket, access key, and secret key when enabled, with an optional session token. Ambient mode requires endpoint and bucket and preserves credentials already available to the runner. Anonymous mode requires endpoint and bucket, supplies no credentials, forces read-only access, and rejects inherited `AWS_ACCESS_KEY_ID` or `AWS_SECRET_ACCESS_KEY` values.

Partial configurations and mixed credential modes fail before sccache is installed. Values written to the job environment must be single-line. Rejected credential values are never printed.

Reusable workflows accept endpoint and bucket as non-secret inputs. A nonempty input takes precedence over its corresponding legacy secret. They forward explicit access keys, secret keys, and session tokens only in static mode. Ambient and anonymous modes receive empty explicit credential inputs even when a caller uses `secrets: inherit`. Direct action callers may acquire credentials before setup. Reusable workflows do not acquire OIDC credentials and only consume credentials already present on the runner.

## Security

Public Pulse Actions entry points may use exact stable semantic-version tags. The validator derives those entry points from `contract/public-api.txt` and rejects moving tags, prereleases, tagged private paths, and tags on other repositories. Third-party actions use full commit SHAs and container actions use image digests. Full commit SHAs remain valid for every remote action.

Workflow validation checks all tracked workflow and `action.yml` files. It validates reference syntax but cannot prove that a tag exists or is protected. The release procedure verifies the annotated tag and GitHub tag ruleset before consumers adopt it. The contract checksum includes every public entry point and every tracked internal action file. Public-surface checks reject private network addresses, private hostnames, runner identities, and estate-specific runner-label conventions.

## Target-cache backend

`cache-target-backend` accepts `github` or `s3` and defaults to `github`. It is available on `setup-rust` and all three Rust reusable workflows. `cache-targets` continues to control whether build directories are cached. S3 requires a complete static compiler-cache configuration; ambient and anonymous modes are not supported for archives. `setup-rust` retains zstd's level 3 default for S3 archives and accepts levels 1 through 19 through `cache-zstd-level`.

S3 archives contain Cargo's target and build directories, including workspace crates. Explicit `cache-workspaces` mappings select the named directory instead. Keys isolate repositories, refs, compiler versions, platforms, paths, dependency and build settings, and source revisions. Restores may use an older entry under the same ref, the PR base branch, or the default branch. Same-repository pull requests save under isolated PR refs; fork PRs and pull_request_target jobs only restore. No S3 failure falls back to GitHub storage. Cache transport failures remain nonfatal and are reported in the provider's logs.

The archive transport requires bucket listing/location and multipart-upload permissions in addition to object reads and writes. The [target-cache policy example](target-cache-policy.json) supplies the full set for `rust/v1/targets/` on Linux and macOS and `rust-target-v1-` on Windows. An existing policy granting these operations under `rust/v1/*` already covers Unix target archives and its lifecycle rule also applies. Windows retains the flat namespace until the provider supports portable S3 object paths. Add only missing permissions alongside existing compiler-cache permissions after replacing the example bucket name.

With S3 enabled, `rust-cache-hit` and `offline` require both the target archive and Cargo registry cache to match their primary keys. `offline` also requires the optional sparse-index cache to match. These outputs report cache state, not proof that an arbitrary subsequent Cargo command can run offline. Registry and sparse-index storage remain on GitHub. Existing GitHub-backend defaults and behavior are unchanged.
