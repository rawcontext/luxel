#!/usr/bin/env bash
set -euo pipefail
source "${TEST_SRCDIR}/bazel_tools/tools/bash/runfiles/runfiles.bash"
script="$(rlocation "$1")"
installer="$(rlocation "$2")/client/cli/install.sh"
cd "$(dirname "$script")/.."
exec bash "$script" "$installer"
