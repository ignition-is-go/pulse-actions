# Public contract

The authoritative entry-point list is [`contract/public-api.txt`](../contract/public-api.txt). Its checksum snapshot records every path, input, output, and default. CI fails if the exported contract changes without an explicit snapshot update.

## Compatibility

The following changes are compatible within v1:

- adding an optional input whose default preserves existing behavior;
- adding an output;
- fixing behavior that contradicts the documented contract;
- updating an internal action without changing exported behavior.

Removing or renaming an entry point, input, secret, or output is breaking. Changing a default, command sequence, cache semantics, or required permission is also breaking.

Runner labels and workflow triggers are deliberately outside this contract. Each calling repository owns them.

## Security

Third-party actions use full commit SHAs and container actions use image digests. Workflow validation checks all tracked workflow and `action.yml` files. Public-surface checks reject private network addresses, private hostnames, runner identities, and estate-specific runner-label conventions.
