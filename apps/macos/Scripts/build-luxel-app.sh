#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Luxel"
CONFIGURATION="${CONFIGURATION:-release}"
PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INFO_PLIST="${PACKAGE_ROOT}/Configuration/Luxel/Info.plist"
ENTITLEMENTS="${ENTITLEMENTS:-${PACKAGE_ROOT}/Configuration/Luxel/Luxel.DeveloperID.entitlements}"
THIRD_PARTY_LICENSES="${PACKAGE_ROOT}/THIRD_PARTY_LICENSES.md"
STRING_CATALOG="${PACKAGE_ROOT}/Sources/LuxelCore/Resources/Localizable.xcstrings"
INSTALL_CLI="${PACKAGE_ROOT}/Scripts/install-cli.sh"
APP_ICON_INSTALLER="${PACKAGE_ROOT}/Scripts/install-luxel-app-icon.sh"
APP_BUNDLE_IDENTIFIER="${APP_BUNDLE_IDENTIFIER:-media.luxel.app.dev}"
APP_DISPLAY_NAME="${APP_DISPLAY_NAME:-Luxel Dev}"
APP_URL_SCHEME="${APP_URL_SCHEME:-luxel-dev}"
APP_PATH="${APP_PATH:-${PACKAGE_ROOT}/dist/${APP_DISPLAY_NAME}.app}"
SIGN_IDENTITY="${SIGN_IDENTITY:-}"

if [[ -z "${SIGN_IDENTITY}" ]]; then
	SIGN_IDENTITY="$(
		security find-identity -v -p codesigning 2>/dev/null |
			awk -F '"' '/"Apple Development: / { print $2; exit }'
	)"
fi

if [[ -z "${SIGN_IDENTITY}" ]]; then
	echo "No Apple Development code signing identity found. Luxel must be signed with a team identity." >&2
	exit 1
fi

if [[ "${SIGN_IDENTITY}" == "-" ]]; then
	echo "Ad-hoc signing is not allowed. Luxel must be signed with a team identity." >&2
	exit 1
fi

cd "${PACKAGE_ROOT}"

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
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string ${APP_NAME}" "${APP_PATH}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIconName string ${APP_NAME}" "${APP_PATH}/Contents/Info.plist"
cp "${BIN_DIR}/${APP_NAME}" "${APP_PATH}/Contents/MacOS/${APP_NAME}"
cp "${BIN_DIR}/luxel-cli" "${APP_PATH}/Contents/MacOS/luxel-cli"
cp "${THIRD_PARTY_LICENSES}" "${APP_PATH}/Contents/Resources/ThirdPartyLicenses.md"
cp "${INSTALL_CLI}" "${APP_PATH}/Contents/Resources/install-cli"
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
        value.replace("\\\\", "\\\\\\\\")
        .replace('"', '\\\\"')
        .replace("\n", "\\\\n")
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
chmod +x "${APP_PATH}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_PATH}/Contents/MacOS/luxel-cli"
chmod +x "${APP_PATH}/Contents/Resources/install-cli"

codesign \
	--force \
	--sign "${SIGN_IDENTITY}" \
	--options runtime \
	--entitlements "${ENTITLEMENTS}" \
	--timestamp \
	"${APP_PATH}"

TEAM_IDENTIFIER="$(
	codesign -dv --verbose=4 "${APP_PATH}" 2>&1 |
		awk -F= '/^TeamIdentifier=/ { print $2; exit }'
)"

if [[ -z "${TEAM_IDENTIFIER}" || "${TEAM_IDENTIFIER}" == "not set" ]]; then
	echo "Code signing did not produce a TeamIdentifier. Luxel must be signed with a team identity." >&2
	exit 1
fi

echo "${APP_PATH}"
