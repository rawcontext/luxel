#!/usr/bin/env bash
set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PACKAGE_ROOT}"

swift test --filter AppDistributionTests
swift test --filter AppDistributionTests -Xswiftc -DLUXEL_MAC_APP_STORE
