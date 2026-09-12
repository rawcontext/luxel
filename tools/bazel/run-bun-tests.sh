#!/usr/bin/env bash
set -euo pipefail
source "${TEST_SRCDIR}/bazel_tools/tools/bash/runfiles/runfiles.bash"
runtime="$(rlocation "$1")"
test_file="$(rlocation "$2")"
exec "$runtime" --preserve-symlinks --preserve-symlinks-main test "$test_file"
