#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

SIGN_IDENTITY="$(
	security find-identity -v -p codesigning 2>/dev/null |
		awk -F '"' '/"Apple Development: / { print $2; exit }'
)"
if [[ -z "${SIGN_IDENTITY}" ]]; then
	echo "No Apple Development code signing identity found." >&2
	exit 1
fi

swift build -c release --product luxel-transcription-benchmark
BIN_DIR="$(swift build -c release --show-bin-path)"
APP_PATH=".bench/transcription/Luxel Transcription Benchmark.app"
EXECUTABLE="luxel-transcription-benchmark"

rm -rf "${APP_PATH}"
mkdir -p "${APP_PATH}/Contents/MacOS"
cp "Configuration/Luxel/Info.plist" "${APP_PATH}/Contents/Info.plist"
cp "${BIN_DIR}/${EXECUTABLE}" "${APP_PATH}/Contents/MacOS/${EXECUTABLE}"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable ${EXECUTABLE}" "${APP_PATH}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.rawcontext.luxel.dev" "${APP_PATH}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Luxel Transcription Benchmark" "${APP_PATH}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName Luxel Transcription Benchmark" "${APP_PATH}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :CFBundleURLTypes" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || true

codesign --force --sign "${SIGN_IDENTITY}" --options runtime --timestamp "${APP_PATH}"
codesign --verify --deep --strict "${APP_PATH}"

ARGS=()
OUTPUT_PATH=""
while [[ $# -gt 0 ]]; do
	case "$1" in
	--manifest | --output)
		flag="$1"
		shift
		if [[ $# -eq 0 ]]; then
			echo "${flag} requires a path." >&2
			exit 1
		fi
		path="$1"
		if [[ "${path}" != /* ]]; then
			path="${PWD}/${path}"
		fi
		ARGS+=("${flag}" "${path}")
		if [[ "${flag}" == "--output" ]]; then
			OUTPUT_PATH="${path}"
		fi
		;;
	*)
		ARGS+=("$1")
		;;
	esac
	shift
done

if [[ -z "${OUTPUT_PATH}" ]]; then
	OUTPUT_PATH="${PWD}/.bench/transcription/results.json"
	ARGS+=("--output" "${OUTPUT_PATH}")
fi

rm -f "${OUTPUT_PATH}" "${OUTPUT_PATH}.error"
/usr/bin/open -W -n "${APP_PATH}" --args "${ARGS[@]}"
if [[ ! -f "${OUTPUT_PATH}" ]]; then
	if [[ -f "${OUTPUT_PATH}.error" ]]; then
		cat "${OUTPUT_PATH}.error" >&2
		rm -f "${OUTPUT_PATH}.error"
	fi
	echo "The benchmark did not produce a result file." >&2
	exit 1
fi
echo "Benchmark results: ${OUTPUT_PATH}"
