#!/usr/bin/env bash
set -euo pipefail

readonly actionlint_version=1.7.12
readonly actionlint_sha256=8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8
readonly shellcheck_version=0.11.0
readonly shellcheck_sha256=b7af85e41cc99489dcc21d66c6d5f3685138f06d34651e6d34b42ec6d54fe6f6
readonly install_dir="${RUNNER_TEMP}/pulse-workflow-validators"

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) ;;
  *)
    printf 'workflow validation requires a Linux x86_64 runner\n' >&2
    exit 1
    ;;
esac

mkdir -p "${install_dir}"

curl -fsSL \
  "https://github.com/rhysd/actionlint/releases/download/v${actionlint_version}/actionlint_${actionlint_version}_linux_amd64.tar.gz" \
  -o "${install_dir}/actionlint.tar.gz"
printf '%s  %s\n' "${actionlint_sha256}" "${install_dir}/actionlint.tar.gz" | sha256sum --check
tar -xzf "${install_dir}/actionlint.tar.gz" -C "${install_dir}" actionlint

curl -fsSL \
  "https://github.com/koalaman/shellcheck/releases/download/v${shellcheck_version}/shellcheck-v${shellcheck_version}.linux.x86_64.tar.gz" \
  -o "${install_dir}/shellcheck.tar.gz"
printf '%s  %s\n' "${shellcheck_sha256}" "${install_dir}/shellcheck.tar.gz" | sha256sum --check
tar -xzf "${install_dir}/shellcheck.tar.gz" -C "${install_dir}" \
  --strip-components=1 "shellcheck-v${shellcheck_version}/shellcheck"

actionlint_args=(
  -ignore 'specifying action "\$/.*" in invalid format'
  -ignore 'reusable workflow call "\$/.*" at "uses" is not following'
)
if [[ -f "${GITHUB_WORKSPACE}/.github/actionlint.yaml" ]]; then
  actionlint_args+=(-config-file "${GITHUB_WORKSPACE}/.github/actionlint.yaml")
fi
PATH="${install_dir}:${PATH}" actionlint "${actionlint_args[@]}"

"${GITHUB_ACTION_PATH}/check-action-pins.sh"
