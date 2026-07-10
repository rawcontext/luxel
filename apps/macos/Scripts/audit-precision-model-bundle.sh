#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
	echo "Usage: audit-precision-model-bundle.sh APP_OR_PACKAGE" >&2
	exit 2
fi

INPUT="$1"
if [[ ! -e "${INPUT}" ]]; then
	echo "Bundle audit input does not exist: ${INPUT}" >&2
	exit 2
fi

TEMPORARY_DIRECTORY=""
cleanup() {
	if [[ -n "${TEMPORARY_DIRECTORY}" ]]; then
		rm -rf "${TEMPORARY_DIRECTORY}"
	fi
}
trap cleanup EXIT

AUDIT_ROOT="${INPUT}"
if [[ "${INPUT}" == *.pkg ]]; then
	TEMPORARY_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/luxel-model-audit.XXXXXX")"
	pkgutil --expand-full "${INPUT}" "${TEMPORARY_DIRECTORY}/expanded"
	AUDIT_ROOT="${TEMPORARY_DIRECTORY}/expanded"
fi

FORBIDDEN_PATH_PATTERN='parakeet-tdt-0\.6b-v3-coreml|Encoder\.mlmodelc|JointDecisionv3\.mlmodelc|aed02740059203c4a87495924f685de3722ae9ce|precision-transcription[^/]*/(staging|releases)'
MATCHES="$(find "${AUDIT_ROOT}" -print | grep -E "${FORBIDDEN_PATH_PATTERN}" || true)"
if [[ -n "${MATCHES}" ]]; then
	echo "Downloaded Precision model content was found in the distribution:" >&2
	echo "${MATCHES}" >&2
	exit 1
fi

echo "Precision model bundle audit passed: ${INPUT}"
