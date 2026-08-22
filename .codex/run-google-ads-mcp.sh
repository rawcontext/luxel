#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
project_directory=${script_directory:h}
environment_file="${project_directory}/.env"

if [[ -f "${environment_file}" ]]; then
  set -a
  source "${environment_file}"
  set +a
fi

exec pipx run \
  --spec "git+https://github.com/googleads/google-ads-mcp.git@ba47210245f2925a130a2770a4d272d5dd0c91cd" \
  google-ads-mcp
