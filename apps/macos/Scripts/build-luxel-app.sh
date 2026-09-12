#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Luxel"
CONFIGURATION="${CONFIGURATION:-release}"
PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPOSITORY_ROOT="$(cd "${PACKAGE_ROOT}/../.." && pwd)"
ENTITLEMENTS="${ENTITLEMENTS:-${PACKAGE_ROOT}/Configuration/Luxel/Luxel.DeveloperID.entitlements}"
CODEC_LICENSE_CHECKER="${PACKAGE_ROOT}/Scripts/check-codec-licenses.sh"
SPEAKER_DIARIZATION_MODEL_AUDITOR="${PACKAGE_ROOT}/Scripts/audit-speaker-diarization-model.sh"
STUDIO_VOICE_MODEL_AUDITOR="${PACKAGE_ROOT}/Scripts/audit-studio-voice-model.sh"
MODNET_MODEL_AUDITOR="${PACKAGE_ROOT}/Scripts/audit-modnet-model.sh"
VAD_MODEL_AUDITOR="${PACKAGE_ROOT}/Scripts/audit-voice-activity-detection-model.sh"
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

"${CODEC_LICENSE_CHECKER}"

bazel build --config="${CONFIGURATION}" --//apps/macos:app_store=false //apps/macos:app
APP_ARCHIVE="${REPOSITORY_ROOT}/$(bazel cquery --config="${CONFIGURATION}" --//apps/macos:app_store=false --output=files //apps/macos:app)"
unpack_bazel_app "${APP_ARCHIVE}"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${APP_BUNDLE_IDENTIFIER}" "${APP_PATH}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName ${APP_DISPLAY_NAME}" "${APP_PATH}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName ${APP_DISPLAY_NAME}" "${APP_PATH}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleURLTypes:0:CFBundleURLName ${APP_BUNDLE_IDENTIFIER}.url" "${APP_PATH}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleURLTypes:0:CFBundleURLSchemes:0 ${APP_URL_SCHEME}" "${APP_PATH}/Contents/Info.plist"
configure_luxel_app_icon
set_luxel_localized_bundle_display_name "${APP_DISPLAY_NAME}"
prepare_luxel_app_executables

codesign \
	--force \
	--sign "${SIGN_IDENTITY}" \
	--options runtime \
	--entitlements "${ENTITLEMENTS}" \
	--timestamp \
	"${APP_PATH}"

codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
bash "${SPEAKER_DIARIZATION_MODEL_AUDITOR}" "${APP_PATH}"
bash "${STUDIO_VOICE_MODEL_AUDITOR}" "${APP_PATH}"
"${MODNET_MODEL_AUDITOR}" "${APP_PATH}"
"${VAD_MODEL_AUDITOR}" "${APP_PATH}"

TEAM_IDENTIFIER="$(
	codesign -dv --verbose=4 "${APP_PATH}" 2>&1 |
		awk -F= '/^TeamIdentifier=/ { print $2; exit }'
)"

if [[ "${TEAM_IDENTIFIER}" != "${APPLE_TEAM_IDENTIFIER}" ]]; then
	echo "Signed TeamIdentifier ${TEAM_IDENTIFIER:-<missing>} does not match ${APPLE_TEAM_IDENTIFIER}." >&2
	exit 1
fi

echo "${APP_PATH}"
