#!/usr/bin/env bash
set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${PACKAGE_ROOT}"

/usr/bin/python3 Scripts/audit-native-codecs.py --self-test
swift test --filter CodecComplianceModelTests
