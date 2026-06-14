#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Luxel"
CONFIGURATION="${CONFIGURATION:-release}"
PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFO_PLIST="${PACKAGE_ROOT}/Configuration/Luxel/Info.plist"
ENTITLEMENTS="${ENTITLEMENTS:-${PACKAGE_ROOT}/Configuration/Luxel/Luxel.DeveloperID.entitlements}"
THIRD_PARTY_LICENSES="${PACKAGE_ROOT}/THIRD_PARTY_LICENSES.md"
INSTALL_CLI="${PACKAGE_ROOT}/Scripts/install-cli.sh"
APP_PATH="${APP_PATH:-${PACKAGE_ROOT}/.build/${APP_NAME}.app}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"

if [[ -z "${SIGN_IDENTITY}" ]]; then
	SIGN_IDENTITY="$(
		security find-identity -v -p codesigning 2>/dev/null |
			awk -F '"' '/"Apple Development: / { print $2; exit }'
	)"
fi

SIGN_IDENTITY="${SIGN_IDENTITY:--}"

cd "${PACKAGE_ROOT}"

swift build --configuration "${CONFIGURATION}" --product "${APP_NAME}"
swift build --configuration "${CONFIGURATION}" --product luxel-cli
BIN_DIR="$(swift build --configuration "${CONFIGURATION}" --show-bin-path)"

rm -rf "${APP_PATH}"
mkdir -p "${APP_PATH}/Contents/MacOS"
mkdir -p "${APP_PATH}/Contents/Resources"
cp "${INFO_PLIST}" "${APP_PATH}/Contents/Info.plist"
cp "${BIN_DIR}/${APP_NAME}" "${APP_PATH}/Contents/MacOS/${APP_NAME}"
cp "${BIN_DIR}/luxel-cli" "${APP_PATH}/Contents/MacOS/luxel-cli"
cp "${THIRD_PARTY_LICENSES}" "${APP_PATH}/Contents/Resources/ThirdPartyLicenses.md"
cp "${INSTALL_CLI}" "${APP_PATH}/Contents/Resources/install-cli"

chmod +x "${APP_PATH}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_PATH}/Contents/MacOS/luxel-cli"
chmod +x "${APP_PATH}/Contents/Resources/install-cli"

if [[ -n "${SIGN_IDENTITY}" ]]; then
	CODESIGN_ARGS=(
		--force
		--sign "${SIGN_IDENTITY}"
		--options runtime
		--entitlements "${ENTITLEMENTS}"
	)

	if [[ "${SIGN_IDENTITY}" == "-" ]]; then
		CODESIGN_ARGS+=(--timestamp=none)
	else
		CODESIGN_ARGS+=(--timestamp)
	fi

	codesign "${CODESIGN_ARGS[@]}" "${APP_PATH}"
fi

echo "${APP_PATH}"
