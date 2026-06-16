#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Luxel"
CONFIGURATION="${CONFIGURATION:-release}"
PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFO_PLIST="${PACKAGE_ROOT}/Configuration/Luxel/Info.plist"
BASE_ENTITLEMENTS="${PACKAGE_ROOT}/Configuration/Luxel/Luxel.MacAppStore.entitlements"
GOOGLE_SERVICE_INFO_PLIST="${GOOGLE_SERVICE_INFO_PLIST:-${PACKAGE_ROOT}/Configuration/Luxel/GoogleService-Info.plist}"
THIRD_PARTY_LICENSES="${PACKAGE_ROOT}/THIRD_PARTY_LICENSES.md"
APP_ICON_GENERATOR="${PACKAGE_ROOT}/Scripts/generate-luxel-app-icon.swift"
OUTPUT_DIR="${OUTPUT_DIR:-${PACKAGE_ROOT}/.build/mas}"
APP_PATH="${APP_PATH:-${OUTPUT_DIR}/${APP_NAME}.app}"
PKG_PATH="${PKG_PATH:-${OUTPUT_DIR}/${APP_NAME}.pkg}"
PROVISIONING_PROFILE="${PROVISIONING_PROFILE:-${MAC_APP_STORE_PROVISIONING_PROFILE:-}}"
APP_STORE_SIGN_IDENTITY="${APP_STORE_SIGN_IDENTITY:-}"
INSTALLER_SIGN_IDENTITY="${INSTALLER_SIGN_IDENTITY:-}"
MARKETING_VERSION="${MARKETING_VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"

find_identity() {
	local pattern="$1"

	security find-identity -v 2>/dev/null |
		awk -F '"' -v pattern="${pattern}" '$0 ~ pattern { print $2; exit }'
}

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

generate_app_icon() {
	local resources_dir="$1"
	local source_png="${OUTPUT_DIR}/${APP_NAME}-icon-1024.png"
	local iconset="${OUTPUT_DIR}/${APP_NAME}.iconset"
	local point_size
	local pixel_size

	require_file "${APP_ICON_GENERATOR}" "App icon generator"

	swift "${APP_ICON_GENERATOR}" "${source_png}" >/dev/null
	rm -rf "${iconset}"
	mkdir -p "${iconset}"

	for point_size in 16 32 128 256 512; do
		pixel_size="${point_size}"
		sips -z "${pixel_size}" "${pixel_size}" "${source_png}" \
			--out "${iconset}/icon_${point_size}x${point_size}.png" >/dev/null

		pixel_size="$((point_size * 2))"
		sips -z "${pixel_size}" "${pixel_size}" "${source_png}" \
			--out "${iconset}/icon_${point_size}x${point_size}@2x.png" >/dev/null
	done

	iconutil --convert icns --output "${resources_dir}/${APP_NAME}.icns" "${iconset}"
}

if [[ -z "${PROVISIONING_PROFILE}" ]]; then
	echo "PROVISIONING_PROFILE or MAC_APP_STORE_PROVISIONING_PROFILE must point to the Mac App Store provisioning profile." >&2
	exit 1
fi

require_file "${PROVISIONING_PROFILE}" "Mac App Store provisioning profile"
require_file "${BASE_ENTITLEMENTS}" "Mac App Store entitlements"

if [[ -z "${APP_STORE_SIGN_IDENTITY}" ]]; then
	APP_STORE_SIGN_IDENTITY="$(
		find_identity '3rd Party Mac Developer Application:|Mac App Distribution:|Apple Distribution:'
	)"
fi

if [[ -z "${APP_STORE_SIGN_IDENTITY}" ]]; then
	echo "No Mac App Store application signing identity found. Set APP_STORE_SIGN_IDENTITY." >&2
	exit 1
fi

if [[ -z "${INSTALLER_SIGN_IDENTITY}" ]]; then
	INSTALLER_SIGN_IDENTITY="$(
		find_identity '3rd Party Mac Developer Installer:|Mac Installer Distribution:'
	)"
fi

if [[ -z "${INSTALLER_SIGN_IDENTITY}" ]]; then
	echo "No Mac App Store installer signing identity found. Set INSTALLER_SIGN_IDENTITY." >&2
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
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string ${APP_NAME}" "${APP_PATH}/Contents/Info.plist"
if [[ -n "${MARKETING_VERSION}" ]]; then
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${MARKETING_VERSION}" "${APP_PATH}/Contents/Info.plist"
fi
if [[ -n "${BUILD_NUMBER}" ]]; then
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER}" "${APP_PATH}/Contents/Info.plist"
fi
/usr/libexec/PlistBuddy -c "Delete :ITSAppUsesNonExemptEncryption" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :ITSAppUsesNonExemptEncryption bool false" "${APP_PATH}/Contents/Info.plist"

cp "${PROVISIONING_PROFILE}" "${APP_PATH}/Contents/embedded.provisionprofile"
cp "${BIN_DIR}/${APP_NAME}" "${APP_PATH}/Contents/MacOS/${APP_NAME}"
cp "${THIRD_PARTY_LICENSES}" "${APP_PATH}/Contents/Resources/ThirdPartyLicenses.md"
generate_app_icon "${APP_PATH}/Contents/Resources"
if [[ -f "${GOOGLE_SERVICE_INFO_PLIST}" ]]; then
	cp "${GOOGLE_SERVICE_INFO_PLIST}" "${APP_PATH}/Contents/Resources/GoogleService-Info.plist"
fi

chmod +x "${APP_PATH}/Contents/MacOS/${APP_NAME}"

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
		awk -F= '/^TeamIdentifier=/ { print $2; exit }'
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

echo "${PKG_PATH}"
