#!/usr/bin/env bash
set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_PATH="${PACKAGE_ROOT}/Tests/Fixtures/input@2x.mp4"
RESULTS_PATH="${PACKAGE_ROOT}/.bench/media/results.json"

cd "${PACKAGE_ROOT}"
bazel build --config=release //apps/macos:media_benchmark
BINARY="${PACKAGE_ROOT}/../../$(bazel cquery --config=release --output=files //apps/macos:media_benchmark)"
exec "${BINARY}" \
	--fixture "${FIXTURE_PATH}" \
	--output "${RESULTS_PATH}" \
	"$@"
