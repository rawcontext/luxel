#!/usr/bin/env bash
set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PACKAGE_ROOT}"

bazel build //apps/macos:codec_artifact_check
bazel test //apps/macos:codec_compliance_tests
