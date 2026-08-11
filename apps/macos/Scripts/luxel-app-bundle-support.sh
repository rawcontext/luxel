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
	cp "${BIN_DIR}/luxel-cli" "${APP_PATH}/Contents/MacOS/luxel-cli"
	cp "${PRIVACY_MANIFEST}" "${APP_PATH}/Contents/Resources/PrivacyInfo.xcprivacy"
	cp "${THIRD_PARTY_LICENSES}" "${APP_PATH}/Contents/Resources/ThirdPartyLicenses.md"
	if [[ -d "${PACKAGE_ROOT}/Vendor/Models/speaker-diarization" ]]; then
		mkdir -p "${APP_PATH}/Contents/Resources/Models"
		cp -R "${PACKAGE_ROOT}/Vendor/Models/speaker-diarization" "${APP_PATH}/Contents/Resources/Models/"
	fi
	if [[ -d "${PACKAGE_ROOT}/Vendor/Models/studio-voice" ]]; then
		mkdir -p "${APP_PATH}/Contents/Resources/Models"
		cp -R "${PACKAGE_ROOT}/Vendor/Models/studio-voice" "${APP_PATH}/Contents/Resources/Models/"
	fi
	mkdir -p "${APP_PATH}/Contents/Resources/Models"
	cp -R "${MODNET_MODEL_DIR}" "${APP_PATH}/Contents/Resources/Models/"
	"${MODNET_MODEL_AUDITOR}" "${APP_PATH}"
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

prepare_luxel_app_executables() {
	chmod +x "${APP_PATH}/Contents/MacOS/${APP_NAME}"
	chmod +x "${APP_PATH}/Contents/MacOS/luxel-cli"
	xcrun strip -x "${APP_PATH}/Contents/MacOS/${APP_NAME}"
	xcrun strip -x "${APP_PATH}/Contents/MacOS/luxel-cli"
}
