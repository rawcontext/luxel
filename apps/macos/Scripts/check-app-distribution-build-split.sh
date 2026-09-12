#!/usr/bin/env bash
set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PACKAGE_ROOT}"

bazel test --//apps/macos:app_store=false //apps/macos:distribution_tests
bazel test --//apps/macos:app_store=true //apps/macos:distribution_tests
