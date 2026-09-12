#!/usr/bin/env bash
set -euo pipefail
source "${TEST_SRCDIR}/bazel_tools/tools/bash/runfiles/runfiles.bash"

# Swift's test rpaths follow xcode-select, which can differ from Bazel's selected Xcode.
developer_dir="$("$(rlocation '{XCODE_LOCATOR}')" "$XCODE_VERSION_OVERRIDE")"
export DYLD_FRAMEWORK_PATH="$developer_dir/Platforms/MacOSX.platform/Developer/Library/Frameworks"
export DYLD_LIBRARY_PATH="$developer_dir/Platforms/MacOSX.platform/Developer/usr/lib"

work="${TEST_TMPDIR}/swift-tests"
mkdir -p "$work"
cp -L "$(rlocation '{BINARY}')" "$work/runner"
cp -RL "$(rlocation '{RESOURCES}')/." "$work/"
cp -RL "$(rlocation '{SNAPSHOT}')" "$work/repository"
chmod -R u+w "$work/repository"
chmod u+x "$work/runner"
export LUXEL_TEST_DATA="$work/repository"

args=(--no-parallel)
if [[ -n "${TESTBRIDGE_TEST_ONLY:-}" ]]; then
  args+=(--filter "$TESTBRIDGE_TEST_ONLY")
fi
exec "$work/runner" "${args[@]}" "$@"
