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

Reusable workflows accept endpoint and bucket as non-secret inputs. A nonempty input takes precedence over its corresponding legacy secret. Direct action callers may acquire credentials before setup. Reusable workflows do not acquire OIDC credentials and only consume credentials already present on the runner.

## Security

Third-party actions use full commit SHAs and container actions use image digests. Workflow validation checks all tracked workflow and `action.yml` files. The contract checksum includes every public entry point and every tracked internal action file. Public-surface checks reject private network addresses, private hostnames, runner identities, and estate-specific runner-label conventions.
