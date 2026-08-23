#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Luxel"
CONFIGURATION="${CONFIGURATION:-release}"
PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFO_PLIST="${PACKAGE_ROOT}/Configuration/Luxel/Info.plist"
PRIVACY_MANIFEST="${PACKAGE_ROOT}/Configuration/Luxel/PrivacyInfo.xcprivacy"
BASE_ENTITLEMENTS="${PACKAGE_ROOT}/Configuration/Luxel/Luxel.MacAppStore.entitlements"
THIRD_PARTY_LICENSES="${PACKAGE_ROOT}/THIRD_PARTY_LICENSES.md"
STRING_CATALOG="${PACKAGE_ROOT}/Sources/LuxelCore/Resources/Localizable.xcstrings"
APP_ICON_INSTALLER="${PACKAGE_ROOT}/Scripts/install-luxel-app-icon.sh"
MODNET_MODEL_DIR="${PACKAGE_ROOT}/Vendor/Models/modnet"
MODNET_MODEL_AUDITOR="${PACKAGE_ROOT}/Scripts/audit-modnet-model.sh"
VAD_MODEL_DIR="${PACKAGE_ROOT}/Vendor/Models/voice-activity-detection"
VAD_MODEL_AUDITOR="${PACKAGE_ROOT}/Scripts/audit-voice-activity-detection-model.sh"
OUTPUT_DIR="${OUTPUT_DIR:-${PACKAGE_ROOT}/.build/mas}"
APP_PATH="${APP_PATH:-${OUTPUT_DIR}/${APP_NAME}.app}"
PKG_PATH="${PKG_PATH:-${OUTPUT_DIR}/${APP_NAME}.pkg}"
PROVISIONING_PROFILE="${PROVISIONING_PROFILE:-${MAC_APP_STORE_PROVISIONING_PROFILE:-}}"
APP_STORE_SIGN_IDENTITY="${APP_STORE_SIGN_IDENTITY:-}"
INSTALLER_SIGN_IDENTITY="${INSTALLER_SIGN_IDENTITY:-}"
MARKETING_VERSION="${MARKETING_VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
APPLE_TEAM_IDENTIFIER="${APPLE_TEAM_IDENTIFIER:-U65DCW9TAK}"

source "${PACKAGE_ROOT}/Scripts/luxel-app-bundle-support.sh"
source "${PACKAGE_ROOT}/Scripts/signing-identity-support.sh"

plist_read() {
	local plist="$1"
	local key_path="$2"

	/usr/libexec/PlistBuddy -c "Print ${key_path}" "${plist}" 2>/dev/null || true
}

require_file() {
	local path="$1"
	local description="$2"

	if [[ ! -f "${path}" ]]; then
		echo "${description} not found at ${path}" >&2
		exit 1
	fi
}

if [[ -z "${PROVISIONING_PROFILE}" ]]; then
	echo "PROVISIONING_PROFILE or MAC_APP_STORE_PROVISIONING_PROFILE must point to the Mac App Store provisioning profile." >&2
	exit 1
fi

require_file "${PROVISIONING_PROFILE}" "Mac App Store provisioning profile"
require_file "${PRIVACY_MANIFEST}" "Privacy manifest"
require_file "${BASE_ENTITLEMENTS}" "Mac App Store entitlements"
"${MODNET_MODEL_AUDITOR}" "${MODNET_MODEL_DIR}"
"${VAD_MODEL_AUDITOR}" "${VAD_MODEL_DIR}"

if [[ -z "${APP_STORE_SIGN_IDENTITY}" ]]; then
	APP_STORE_SIGN_IDENTITY="$(
		find_signing_identity_for_team \
			'3rd Party Mac Developer Application:|Mac App Distribution:|Apple Distribution:' \
			"${APPLE_TEAM_IDENTIFIER}"
	)"
fi

if [[ -z "${APP_STORE_SIGN_IDENTITY}" ]]; then
	echo "No Mac App Store application signing identity found for team ${APPLE_TEAM_IDENTIFIER}." >&2
	exit 1
fi

if [[ -z "${INSTALLER_SIGN_IDENTITY}" ]]; then
	INSTALLER_SIGN_IDENTITY="$(
		find_signing_identity_for_team \
			'3rd Party Mac Developer Installer:|Mac Installer Distribution:' \
			"${APPLE_TEAM_IDENTIFIER}"
	)"
fi

if [[ -z "${INSTALLER_SIGN_IDENTITY}" ]]; then
	echo "No Mac App Store installer signing identity found for team ${APPLE_TEAM_IDENTIFIER}." >&2
	exit 1
fi

mkdir -p "${OUTPUT_DIR}"

PROFILE_PLIST="${OUTPUT_DIR}/embedded-profile.plist"
RESOLVED_ENTITLEMENTS="${OUTPUT_DIR}/${APP_NAME}.MacAppStore.resolved.entitlements"

security cms -D -i "${PROVISIONING_PROFILE}" >"${PROFILE_PLIST}"

BUNDLE_IDENTIFIER="$(plist_read "${INFO_PLIST}" ":CFBundleIdentifier")"
PROFILE_APP_IDENTIFIER="$(plist_read "${PROFILE_PLIST}" ":Entitlements:application-identifier")"
PROFILE_TEAM_IDENTIFIER="$(plist_read "${PROFILE_PLIST}" ":Entitlements:com.apple.developer.team-identifier")"
PROFILE_BETA_REPORTS_ACTIVE="$(plist_read "${PROFILE_PLIST}" ":Entitlements:beta-reports-active")"

if [[ -z "${BUNDLE_IDENTIFIER}" ]]; then
	echo "CFBundleIdentifier is missing from ${INFO_PLIST}." >&2
	exit 1
fi

if [[ -z "${PROFILE_TEAM_IDENTIFIER}" ]]; then
	echo "Provisioning profile is missing com.apple.developer.team-identifier." >&2
	exit 1
fi

if [[ "${PROFILE_TEAM_IDENTIFIER}" != "${APPLE_TEAM_IDENTIFIER}" ]]; then
	echo "Provisioning profile team ${PROFILE_TEAM_IDENTIFIER} does not match ${APPLE_TEAM_IDENTIFIER}." >&2
	exit 1
fi

EXPECTED_APP_IDENTIFIER="${PROFILE_TEAM_IDENTIFIER}.${BUNDLE_IDENTIFIER}"
if [[ -n "${PROFILE_APP_IDENTIFIER}" && "${PROFILE_APP_IDENTIFIER}" != "${EXPECTED_APP_IDENTIFIER}" ]]; then
	echo "Provisioning profile App ID ${PROFILE_APP_IDENTIFIER} does not match ${EXPECTED_APP_IDENTIFIER}." >&2
	exit 1
fi

cp "${BASE_ENTITLEMENTS}" "${RESOLVED_ENTITLEMENTS}"
/usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string ${EXPECTED_APP_IDENTIFIER}" "${RESOLVED_ENTITLEMENTS}"
/usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string ${PROFILE_TEAM_IDENTIFIER}" "${RESOLVED_ENTITLEMENTS}"
if [[ "${PROFILE_BETA_REPORTS_ACTIVE}" == "true" ]]; then
	/usr/libexec/PlistBuddy -c "Add :beta-reports-active bool true" "${RESOLVED_ENTITLEMENTS}"
fi

cd "${PACKAGE_ROOT}"

swift build \
	--configuration "${CONFIGURATION}" \
	-Xswiftc -DLUXEL_MAC_APP_STORE \
	--product "${APP_NAME}"
BIN_DIR="$(swift build --configuration "${CONFIGURATION}" --show-bin-path)"

rm -rf "${APP_PATH}" "${PKG_PATH}"
mkdir -p "${APP_PATH}/Contents/MacOS"
mkdir -p "${APP_PATH}/Contents/Resources"

cp "${INFO_PLIST}" "${APP_PATH}/Contents/Info.plist"
configure_luxel_app_icon
if [[ -n "${MARKETING_VERSION}" ]]; then
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${MARKETING_VERSION}" "${APP_PATH}/Contents/Info.plist"
fi
if [[ -n "${BUILD_NUMBER}" ]]; then
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${APP_PATH}/Contents/Info.plist"
fi
/usr/libexec/PlistBuddy -c "Delete :ITSAppUsesNonExemptEncryption" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :ITSAppUsesNonExemptEncryption bool false" "${APP_PATH}/Contents/Info.plist"

cp "${PROVISIONING_PROFILE}" "${APP_PATH}/Contents/embedded.provisionprofile"
copy_luxel_app_payload
copy_luxel_app_resources
while IFS= read -r -d '' bundle_plist; do
	if ! /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "${bundle_plist}" >/dev/null 2>&1; then
		bundle_name="$(basename "$(dirname "${bundle_plist}")" .bundle)"
		bundle_identifier_suffix="$(printf "%s" "${bundle_name}" | tr '[:upper:]_' '[:lower:].')"
		/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string ${BUNDLE_IDENTIFIER}.${bundle_identifier_suffix}" "${bundle_plist}"
	fi
done < <(find "${APP_PATH}/Contents/Resources" -maxdepth 2 -path '*.bundle/Info.plist' -type f -print0)
if [[ ! -d "${APP_PATH}/Contents/Resources/Luxel_LuxelCore.bundle" ]]; then
	echo "LuxelCore resource bundle was not copied into the app bundle." >&2
	exit 1
fi

prepare_luxel_app_executables

codesign \
	--force \
	--sign "${APP_STORE_SIGN_IDENTITY}" \
	--options runtime \
	--entitlements "${RESOLVED_ENTITLEMENTS}" \
	--timestamp \
	"${APP_PATH}"

codesign --verify --deep --strict --verbose=2 "${APP_PATH}"

SIGNED_TEAM_IDENTIFIER="$(
	codesign -dv --verbose=4 "${APP_PATH}" 2>&1 |
		awk -F= '/^TeamIdentifier=/ { print $2 }'
)"

if [[ "${SIGNED_TEAM_IDENTIFIER}" != "${PROFILE_TEAM_IDENTIFIER}" ]]; then
	echo "Signed TeamIdentifier ${SIGNED_TEAM_IDENTIFIER:-<missing>} does not match profile team ${PROFILE_TEAM_IDENTIFIER}." >&2
	exit 1
fi

productbuild \
	--sign "${INSTALLER_SIGN_IDENTITY}" \
	--component "${APP_PATH}" /Applications \
	"${PKG_PATH}"

pkgutil --check-signature "${PKG_PATH}" >/dev/null
"${MODNET_MODEL_AUDITOR}" "${PKG_PATH}"
"${VAD_MODEL_AUDITOR}" "${PKG_PATH}"

echo "${PKG_PATH}"
