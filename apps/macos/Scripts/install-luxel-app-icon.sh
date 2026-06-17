#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-Luxel}"
RESOURCES_DIR="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
APP_ICON_SOURCE="${APP_ICON_SOURCE:-${PACKAGE_ROOT}/Configuration/Luxel/${APP_NAME}.icon}"
ICON_WORK_DIR="${ICON_WORK_DIR:-${PACKAGE_ROOT}/.build/app-icon}"
ICON_COMPOSER_TOOL="${ICON_COMPOSER_TOOL:-/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool}"
ACTOOL="${ACTOOL:-/Applications/Xcode.app/Contents/Developer/usr/bin/actool}"

if [[ -z "${RESOURCES_DIR}" ]]; then
	echo "Usage: install-luxel-app-icon.sh <app-resources-dir>" >&2
	exit 1
fi

if [[ ! -d "${APP_ICON_SOURCE}" ]]; then
	echo "Icon Composer source not found at ${APP_ICON_SOURCE}" >&2
	exit 1
fi

if [[ ! -x "${ICON_COMPOSER_TOOL}" ]]; then
	echo "Icon Composer export tool not found at ${ICON_COMPOSER_TOOL}" >&2
	exit 1
fi

if [[ ! -x "${ACTOOL}" ]]; then
	echo "actool not found at ${ACTOOL}" >&2
	exit 1
fi

mkdir -p "${RESOURCES_DIR}" "${ICON_WORK_DIR}"

SOURCE_PNG="${ICON_WORK_DIR}/${APP_NAME}-icon-1024.png"
ICONSET="${ICON_WORK_DIR}/${APP_NAME}.iconset"
PARTIAL_INFO_PLIST="${ICON_WORK_DIR}/${APP_NAME}-icon-partial-info.plist"

"${ICON_COMPOSER_TOOL}" "${APP_ICON_SOURCE}" \
	--export-image \
	--output-file "${SOURCE_PNG}" \
	--platform macOS \
	--rendition Default \
	--width 1024 \
	--height 1024 \
	--scale 1 >/dev/null

rm -rf "${ICONSET}"
mkdir -p "${ICONSET}"

for point_size in 16 32 128 256 512; do
	sips -z "${point_size}" "${point_size}" "${SOURCE_PNG}" \
		--out "${ICONSET}/icon_${point_size}x${point_size}.png" >/dev/null

	pixel_size="$((point_size * 2))"
	sips -z "${pixel_size}" "${pixel_size}" "${SOURCE_PNG}" \
		--out "${ICONSET}/icon_${point_size}x${point_size}@2x.png" >/dev/null
done

iconutil --convert icns --output "${RESOURCES_DIR}/${APP_NAME}.icns" "${ICONSET}"

"${ACTOOL}" "${APP_ICON_SOURCE}" \
	--compile "${RESOURCES_DIR}" \
	--app-icon "${APP_NAME}" \
	--include-all-app-icons \
	--platform macosx \
	--target-device mac \
	--minimum-deployment-target 26.0 \
	--standalone-icon-behavior none \
	--output-partial-info-plist "${PARTIAL_INFO_PLIST}" >/dev/null
