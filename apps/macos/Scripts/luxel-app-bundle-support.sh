#!/usr/bin/env bash

configure_luxel_app_icon() {
	local app_info_plist="${APP_PATH}/Contents/Info.plist"

	/usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "${app_info_plist}" 2>/dev/null || true
	/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string ${APP_NAME}" "${app_info_plist}"
	/usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "${app_info_plist}" 2>/dev/null || true
	/usr/libexec/PlistBuddy -c "Add :CFBundleIconName string ${APP_NAME}" "${app_info_plist}"
}

copy_luxel_app_payload() {
	cp "${BIN_DIR}/${APP_NAME}" "${APP_PATH}/Contents/MacOS/${APP_NAME}"
	cp "${PRIVACY_MANIFEST}" "${APP_PATH}/Contents/Resources/PrivacyInfo.xcprivacy"
	cp "${THIRD_PARTY_LICENSES}" "${APP_PATH}/Contents/Resources/ThirdPartyLicenses.md"
	cp "${PACKAGE_ROOT}/../../LICENSE" "${APP_PATH}/Contents/Resources/LICENSE.txt"
	mkdir -p "${APP_PATH}/Contents/Resources/Models"
	cp -R "${SPEAKER_DIARIZATION_MODEL_DIR}" "${APP_PATH}/Contents/Resources/Models/"
	bash "${SPEAKER_DIARIZATION_MODEL_AUDITOR}" "${APP_PATH}"
	cp -R "${STUDIO_VOICE_MODEL_DIR}" "${APP_PATH}/Contents/Resources/Models/"
	bash "${STUDIO_VOICE_MODEL_AUDITOR}" "${APP_PATH}"
	cp -R "${MODNET_MODEL_DIR}" "${APP_PATH}/Contents/Resources/Models/"
	"${MODNET_MODEL_AUDITOR}" "${APP_PATH}"
	cp -R "${VAD_MODEL_DIR}" "${APP_PATH}/Contents/Resources/Models/"
	"${VAD_MODEL_AUDITOR}" "${APP_PATH}"
}

copy_luxel_app_resources() {
	"${APP_ICON_INSTALLER}" "${APP_PATH}/Contents/Resources"
	find "${BIN_DIR}" -maxdepth 1 -name '*.bundle' -type d -exec cp -R {} "${APP_PATH}/Contents/Resources/" \;
	find "${BIN_DIR}" -maxdepth 2 -name '*.lproj' -type d -exec cp -R {} "${APP_PATH}/Contents/Resources/" \;
	if [[ -d "${PACKAGE_ROOT}/Configuration/Luxel/Localizations" ]]; then
		find "${PACKAGE_ROOT}/Configuration/Luxel/Localizations" -maxdepth 1 -name '*.lproj' -type d -exec cp -R {} "${APP_PATH}/Contents/Resources/" \;
	fi
	if [[ -f "${STRING_CATALOG}" ]]; then
		python3 \
			"${PACKAGE_ROOT}/Scripts/compile-luxel-string-catalog.py" \
			"${STRING_CATALOG}" \
			"${APP_PATH}/Contents/Resources" \
			"${APP_PATH}/Contents/Resources/Luxel_LuxelCore.bundle"
	fi
}

set_luxel_localized_bundle_display_name() {
	local display_name="$1"
	local info_plist_strings

	while IFS= read -r -d '' info_plist_strings; do
		/usr/libexec/PlistBuddy \
			-c "Set :CFBundleDisplayName ${display_name}" \
			-c "Set :CFBundleName ${display_name}" \
			"${info_plist_strings}"
	done < <(
		find "${APP_PATH}/Contents/Resources" \
			-maxdepth 2 \
			-path '*.lproj/InfoPlist.strings' \
			-type f \
			-print0
	)
}

prepare_luxel_app_executables() {
	chmod +x "${APP_PATH}/Contents/MacOS/${APP_NAME}"
	xcrun strip -x "${APP_PATH}/Contents/MacOS/${APP_NAME}"
}
