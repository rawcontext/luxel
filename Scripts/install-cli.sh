#!/usr/bin/env bash
set -euo pipefail

DESTINATION="${1:-${HOME}/bin/luxel}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_CONTENTS="$(cd "${SCRIPT_DIR}/.." && pwd)"
CLI_PATH="${BUNDLE_CONTENTS}/MacOS/luxel-cli"

if [[ ! -x "${CLI_PATH}" ]]; then
	echo "luxel-cli not found at ${CLI_PATH}" >&2
	exit 1
fi

mkdir -p "$(dirname "${DESTINATION}")"
ln -sf "${CLI_PATH}" "${DESTINATION}"
echo "${DESTINATION}"
