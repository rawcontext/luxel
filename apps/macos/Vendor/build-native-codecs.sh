#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"${ROOT}/Vendor/build-libopus.sh"
"${ROOT}/Vendor/build-libvpx.sh"
"${ROOT}/Vendor/build-libsvtav1.sh"
