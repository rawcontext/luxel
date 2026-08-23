#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

/usr/bin/python3 "${ROOT}/Vendor/generate-native-codec-manifest.py" --verify-toolchain-only
"${ROOT}/Vendor/build-libopus.sh"
"${ROOT}/Vendor/build-libvpx.sh"
"${ROOT}/Vendor/build-libsvtav1.sh"
/usr/bin/python3 "${ROOT}/Vendor/generate-native-codec-manifest.py"
/usr/bin/python3 "${ROOT}/Scripts/audit-native-codecs.py" --verify-installed-toolchain
