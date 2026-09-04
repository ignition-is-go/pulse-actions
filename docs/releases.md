# Releases

Stable releases use annotated semantic-version tags such as `v1.0.0`. Tags are immutable.

Callers pin the tag's full commit SHA, not the movable major version. A trailing tag comment lets Dependabot and reviewers identify the intended release. Dependabot keeps third-party action pins current in this repository.

Breaking public-contract changes require a new major version. Internal files under `.github/actions` are not public entry points.
