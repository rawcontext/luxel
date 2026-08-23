#!/usr/bin/env bash
set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_PATH="${PACKAGE_ROOT}/Tests/Fixtures/input@2x.mp4"
RESULTS_PATH="${PACKAGE_ROOT}/.bench/media/results.json"

cd "${PACKAGE_ROOT}"
swift build --configuration release --product luxel-media-benchmark
BIN_DIRECTORY="$(swift build --configuration release --show-bin-path)"
exec "${BIN_DIRECTORY}/luxel-media-benchmark" \
	--fixture "${FIXTURE_PATH}" \
	--output "${RESULTS_PATH}" \
	"$@"
