#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Luxel"
CONFIGURATION="${CONFIGURATION:-release}"
PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFO_PLIST="${PACKAGE_ROOT}/Configuration/Luxel/Info.plist"
BASE_ENTITLEMENTS="${PACKAGE_ROOT}/Configuration/Luxel/Luxel.MacAppStore.entitlements"
CLI_ENTITLEMENTS="${PACKAGE_ROOT}/Configuration/Luxel/LuxelCLI.MacAppStore.entitlements"
THIRD_PARTY_LICENSES="${PACKAGE_ROOT}/THIRD_PARTY_LICENSES.md"
STRING_CATALOG="${PACKAGE_ROOT}/Sources/LuxelCore/Resources/Localizable.xcstrings"
APP_ICON_INSTALLER="${PACKAGE_ROOT}/Scripts/install-luxel-app-icon.sh"
PRECISION_MODEL_AUDITOR="${PACKAGE_ROOT}/Scripts/audit-precision-model-bundle.sh"
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

if [[ -z "${PROVISIONING_PROFILE}" ]]; then
	echo "PROVISIONING_PROFILE or MAC_APP_STORE_PROVISIONING_PROFILE must point to the Mac App Store provisioning profile." >&2
	exit 1
fi

require_file "${PROVISIONING_PROFILE}" "Mac App Store provisioning profile"
require_file "${BASE_ENTITLEMENTS}" "Mac App Store entitlements"
require_file "${CLI_ENTITLEMENTS}" "Mac App Store command line tool entitlements"

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
swift build \
	--configuration "${CONFIGURATION}" \
	-Xswiftc -DLUXEL_MAC_APP_STORE \
	--product luxel-cli
BIN_DIR="$(swift build --configuration "${CONFIGURATION}" --show-bin-path)"

rm -rf "${APP_PATH}" "${PKG_PATH}"
mkdir -p "${APP_PATH}/Contents/MacOS"
mkdir -p "${APP_PATH}/Contents/Resources"

cp "${INFO_PLIST}" "${APP_PATH}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string ${APP_NAME}" "${APP_PATH}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIconName string ${APP_NAME}" "${APP_PATH}/Contents/Info.plist"
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
cp "${BIN_DIR}/luxel-cli" "${APP_PATH}/Contents/MacOS/luxel-cli"
cp "${THIRD_PARTY_LICENSES}" "${APP_PATH}/Contents/Resources/ThirdPartyLicenses.md"
if [[ -d "${PACKAGE_ROOT}/Vendor/Models/speaker-diarization" ]]; then
	mkdir -p "${APP_PATH}/Contents/Resources/Models"
	cp -R "${PACKAGE_ROOT}/Vendor/Models/speaker-diarization" "${APP_PATH}/Contents/Resources/Models/"
fi
"${APP_ICON_INSTALLER}" "${APP_PATH}/Contents/Resources"
find "${BIN_DIR}" -maxdepth 1 -name '*.bundle' -type d -exec cp -R {} "${APP_PATH}/Contents/Resources/" \;
find "${BIN_DIR}" -maxdepth 2 -name '*.lproj' -type d -exec cp -R {} "${APP_PATH}/Contents/Resources/" \;
if [[ -d "${PACKAGE_ROOT}/Configuration/Luxel/Localizations" ]]; then
	find "${PACKAGE_ROOT}/Configuration/Luxel/Localizations" -maxdepth 1 -name '*.lproj' -type d -exec cp -R {} "${APP_PATH}/Contents/Resources/" \;
fi
if [[ -f "${STRING_CATALOG}" ]]; then
	python3 - "${STRING_CATALOG}" "${APP_PATH}/Contents/Resources" "${APP_PATH}/Contents/Resources/Luxel_LuxelCore.bundle" <<'PY'
import json
import pathlib
import sys

catalog_path = pathlib.Path(sys.argv[1])
output_roots = [pathlib.Path(path) for path in sys.argv[2:] if pathlib.Path(path).exists()]

with catalog_path.open(encoding="utf-8") as catalog_file:
    catalog = json.load(catalog_file)

locales = sorted({
    locale
    for entry in catalog.get("strings", {}).values()
    for locale in entry.get("localizations", {})
})


def escaped(value):
    return (
        value.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
    )


for output_root in output_roots:
    for locale in locales:
        lproj = output_root / f"{locale}.lproj"
        lproj.mkdir(parents=True, exist_ok=True)
        strings_file = lproj / "Localizable.strings"
        with strings_file.open("w", encoding="utf-8") as output:
            for key, entry in sorted(catalog.get("strings", {}).items()):
                unit = entry.get("localizations", {}).get(locale, {}).get("stringUnit", {})
                value = unit.get("value")
                if value:
                    output.write(f'"{escaped(key)}" = "{escaped(value)}";\n')
PY
fi
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

"${PRECISION_MODEL_AUDITOR}" "${APP_PATH}"

chmod +x "${APP_PATH}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_PATH}/Contents/MacOS/luxel-cli"

xcrun strip -x "${APP_PATH}/Contents/MacOS/${APP_NAME}"
xcrun strip -x "${APP_PATH}/Contents/MacOS/luxel-cli"

codesign \
	--force \
	--sign "${APP_STORE_SIGN_IDENTITY}" \
	--options runtime \
	--entitlements "${CLI_ENTITLEMENTS}" \
	--timestamp \
	"${APP_PATH}/Contents/MacOS/luxel-cli"

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
"${PRECISION_MODEL_AUDITOR}" "${PKG_PATH}"

echo "${PKG_PATH}"
