# Releases

Stable releases use annotated semantic-version tags such as `v1.0.0`. Tags are immutable.

Callers may use an exact stable tag such as `v1.1.0` for the public Pulse Actions entry points. Moving tags such as `v1`, branches, prereleases, build suffixes, private implementation paths, and tags from other repositories are rejected. Third-party actions remain pinned to full commit SHAs. A full commit SHA remains valid for Pulse Actions acceptance testing before a release tag exists.

Static workflow validation proves only that a reference has the permitted shape. It cannot prove that a tag exists, is annotated, resolves to the accepted commit, or is protected against updates and deletion. Before updating consumers, a release operator must:

1. Merge and accept the release commit by its full SHA.
2. Verify that the active `refs/tags/v*` ruleset blocks updates and deletion without a bypass.
3. Create an annotated `vMAJOR.MINOR.PATCH` tag at the accepted commit.
4. Verify the tag object and its peeled commit through the GitHub API or `git ls-remote`.
5. Update consumers to the exact release tag.

Dependabot keeps third-party action pins current in this repository.

Breaking public-contract changes require a new major version. Internal files under `.github/actions` are not public entry points.
