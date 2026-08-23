#!/bin/zsh

set -euo pipefail

script_directory=${0:A:h}
project_directory=${script_directory:h}
environment_file="${project_directory}/.env"
expected_pipx_version=1.16.7

if [[ -f "${environment_file}" ]]; then
  set -a
  source "${environment_file}"
  set +a
fi

if ! command -v pipx >/dev/null 2>&1; then
  print -u2 "Google Ads MCP requires pipx ${expected_pipx_version}."
  exit 1
fi

actual_pipx_version=$(pipx --version)
if [[ "${actual_pipx_version}" != "${expected_pipx_version}" ]]; then
  print -u2 "Google Ads MCP requires pipx ${expected_pipx_version}; found ${actual_pipx_version}."
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  print -u2 "Google Ads MCP requires the Python version pinned in .tool-versions."
  exit 1
fi

expected_python_version=$(awk '$1 == "python" { print $2 }' "${project_directory}/.tool-versions")
actual_python_version=$(python3 -c 'import platform; print(platform.python_version())')
python_executable=$(python3 -c 'import sys; print(sys.executable)')
if [[ -z "${expected_python_version}" || "${actual_python_version}" != "${expected_python_version}" ]]; then
  print -u2 \
    "Google Ads MCP requires Python ${expected_python_version:-<missing pin>}; found ${actual_python_version}."
  exit 1
fi

exec pipx run \
  --python "${python_executable}" \
  --spec "git+https://github.com/googleads/google-ads-mcp.git@ba47210245f2925a130a2770a4d272d5dd0c91cd" \
  google-ads-mcp
