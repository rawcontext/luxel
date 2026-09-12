#!/usr/bin/env bash

configure_luxel_app_icon() {
	local app_info_plist="${APP_PATH}/Contents/Info.plist"

	/usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "${app_info_plist}" 2>/dev/null || true
	/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string ${APP_NAME}" "${app_info_plist}"
	/usr/libexec/PlistBuddy -c "Delete :CFBundleIconName" "${app_info_plist}" 2>/dev/null || true
	/usr/libexec/PlistBuddy -c "Add :CFBundleIconName string ${APP_NAME}" "${app_info_plist}"
}

unpack_bazel_app() {
	local archive="$1"
	local staging
	staging="$(mktemp -d "${TMPDIR:-/tmp}/luxel-bazel-bundle.XXXXXX")"
	ditto -x -k "${archive}" "${staging}"
	test -d "${staging}/Luxel.app"
	mkdir -p "$(dirname "${APP_PATH}")"
	rm -rf "${APP_PATH}"
	mv "${staging}/Luxel.app" "${APP_PATH}"
	rmdir "${staging}"
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
