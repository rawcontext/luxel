#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec /usr/bin/python3 "${SCRIPT_DIRECTORY}/audit-bundled-model.py" voice-activity-detection "$@"
