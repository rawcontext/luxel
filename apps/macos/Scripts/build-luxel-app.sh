#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Luxel"
CONFIGURATION="${CONFIGURATION:-release}"
PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFO_PLIST="${PACKAGE_ROOT}/Configuration/Luxel/Info.plist"
PRIVACY_MANIFEST="${PACKAGE_ROOT}/Configuration/Luxel/PrivacyInfo.xcprivacy"
ENTITLEMENTS="${ENTITLEMENTS:-${PACKAGE_ROOT}/Configuration/Luxel/Luxel.DeveloperID.entitlements}"
THIRD_PARTY_LICENSES="${PACKAGE_ROOT}/THIRD_PARTY_LICENSES.md"
CLI_MANPAGE="${PACKAGE_ROOT}/Documentation/luxel.1"
STRING_CATALOG="${PACKAGE_ROOT}/Sources/LuxelCore/Resources/Localizable.xcstrings"
APP_ICON_INSTALLER="${PACKAGE_ROOT}/Scripts/install-luxel-app-icon.sh"
MODNET_MODEL_DIR="${PACKAGE_ROOT}/Vendor/Models/modnet"
MODNET_MODEL_AUDITOR="${PACKAGE_ROOT}/Scripts/audit-modnet-model.sh"
APP_BUNDLE_IDENTIFIER="${APP_BUNDLE_IDENTIFIER:-com.rawcontext.luxel.dev}"
APP_DISPLAY_NAME="${APP_DISPLAY_NAME:-Luxel Dev}"
APP_URL_SCHEME="${APP_URL_SCHEME:-luxel-dev}"
APP_PATH="${APP_PATH:-${PACKAGE_ROOT}/dist/${APP_DISPLAY_NAME}.app}"
APPLE_TEAM_IDENTIFIER="${APPLE_TEAM_IDENTIFIER:-U65DCW9TAK}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"

source "${PACKAGE_ROOT}/Scripts/luxel-app-bundle-support.sh"
source "${PACKAGE_ROOT}/Scripts/signing-identity-support.sh"

if [[ -z "${SIGN_IDENTITY}" ]]; then
	SIGN_IDENTITY="$(
		find_signing_identity_for_team 'Apple Development:' "${APPLE_TEAM_IDENTIFIER}"
	)"
fi

if [[ -z "${SIGN_IDENTITY}" ]]; then
	echo "No Apple Development code signing identity found for team ${APPLE_TEAM_IDENTIFIER}." >&2
	exit 1
fi

if [[ "${SIGN_IDENTITY}" == "-" ]]; then
	echo "Ad-hoc signing is not allowed. Luxel must be signed with a team identity." >&2
	exit 1
fi

cd "${PACKAGE_ROOT}"

"${MODNET_MODEL_AUDITOR}" "${MODNET_MODEL_DIR}"

swift build --configuration "${CONFIGURATION}" --product "${APP_NAME}"
swift build --configuration "${CONFIGURATION}" --product luxel-cli
BIN_DIR="$(swift build --configuration "${CONFIGURATION}" --show-bin-path)"

rm -rf "${APP_PATH}"
mkdir -p "${APP_PATH}/Contents/MacOS"
mkdir -p "${APP_PATH}/Contents/Resources"
cp "${INFO_PLIST}" "${APP_PATH}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${APP_BUNDLE_IDENTIFIER}" "${APP_PATH}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName ${APP_DISPLAY_NAME}" "${APP_PATH}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName ${APP_DISPLAY_NAME}" "${APP_PATH}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleURLTypes:0:CFBundleURLName ${APP_BUNDLE_IDENTIFIER}.url" "${APP_PATH}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleURLTypes:0:CFBundleURLSchemes:0 ${APP_URL_SCHEME}" "${APP_PATH}/Contents/Info.plist"
configure_luxel_app_icon
copy_luxel_app_payload
if [[ -f "${CLI_MANPAGE}" ]]; then
	mkdir -p "${APP_PATH}/Contents/Resources/man/man1"
	cp "${CLI_MANPAGE}" "${APP_PATH}/Contents/Resources/man/man1/luxel.1"
fi
copy_luxel_app_resources
prepare_luxel_app_executables

codesign \
	--force \
	--sign "${SIGN_IDENTITY}" \
	--options runtime \
	--timestamp \
	"${APP_PATH}/Contents/MacOS/luxel-cli"

codesign \
	--force \
	--sign "${SIGN_IDENTITY}" \
	--options runtime \
	--entitlements "${ENTITLEMENTS}" \
	--timestamp \
	"${APP_PATH}"

codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
"${MODNET_MODEL_AUDITOR}" "${APP_PATH}"

EXPECTED_AUTOMATION_URL="${APP_URL_SCHEME}://stop"
ACTUAL_AUTOMATION_URL="$("${APP_PATH}/Contents/MacOS/luxel-cli" stop --print-url)"
if [[ "${ACTUAL_AUTOMATION_URL}" != "${EXPECTED_AUTOMATION_URL}" ]]; then
	echo "Bundled CLI emitted ${ACTUAL_AUTOMATION_URL}; expected ${EXPECTED_AUTOMATION_URL}." >&2
	exit 1
fi

TEAM_IDENTIFIER="$(
	codesign -dv --verbose=4 "${APP_PATH}" 2>&1 |
		awk -F= '/^TeamIdentifier=/ { print $2; exit }'
)"

if [[ "${TEAM_IDENTIFIER}" != "${APPLE_TEAM_IDENTIFIER}" ]]; then
	echo "Signed TeamIdentifier ${TEAM_IDENTIFIER:-<missing>} does not match ${APPLE_TEAM_IDENTIFIER}." >&2
	exit 1
fi

echo "${APP_PATH}"
