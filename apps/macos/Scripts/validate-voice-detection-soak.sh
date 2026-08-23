#!/usr/bin/env bash
set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${PACKAGE_ROOT}/dist/Luxel Dev.app"
APP_EXECUTABLE="${APP_PATH}/Contents/MacOS/Luxel"
EXPECTED_BUNDLE_IDENTIFIER="com.rawcontext.luxel.dev"
EXPECTED_DISPLAY_NAME="Luxel Dev"
EXPECTED_URL_SCHEME="luxel-dev"
EXPECTED_TEAM_IDENTIFIER="U65DCW9TAK"
DEFAULT_DURATION_SECONDS=28800
DEFAULT_INTERVAL_SECONDS=60

duration_seconds="${DEFAULT_DURATION_SECONDS}"
interval_seconds="${DEFAULT_INTERVAL_SECONDS}"
recordings_directory="${HOME}/Movies/Luxel"
input_device=""
output_file=""
listening_confirmed=false

usage() {
	cat <<'EOF'
Usage: validate-voice-detection-soak.sh --confirm-listening --input-device NAME --output FILE [options]

Options:
  --confirm-listening          Confirm the signed app visibly reports Listening before sampling.
  --input-device NAME          Record the selected input device in the summary.
  --output FILE                Write timestamp, elapsed seconds, CPU, and RSS samples as CSV.
  --recordings-directory PATH  Directory selected in Luxel (default: ~/Movies/Luxel).
  --duration-seconds NUMBER    Soak duration (default: 28800, eight hours).
  --interval-seconds NUMBER    Sampling interval (default: 60).
  --help                       Show this help.

The script requires the default Apple Development-signed Luxel Dev.app identity.
It never launches or modifies /Applications/Luxel.app.
EOF
}

fail() {
	echo "Voice detection soak failed: $*" >&2
	exit 1
}

while [[ $# -gt 0 ]]; do
	case "$1" in
	--confirm-listening)
		listening_confirmed=true
		shift
		;;
	--input-device)
		[[ $# -ge 2 ]] || fail "--input-device requires a value"
		input_device="$2"
		shift 2
		;;
	--output)
		[[ $# -ge 2 ]] || fail "--output requires a value"
		output_file="$2"
		shift 2
		;;
	--recordings-directory)
		[[ $# -ge 2 ]] || fail "--recordings-directory requires a value"
		recordings_directory="$2"
		shift 2
		;;
	--duration-seconds)
		[[ $# -ge 2 ]] || fail "--duration-seconds requires a value"
		duration_seconds="$2"
		shift 2
		;;
	--interval-seconds)
		[[ $# -ge 2 ]] || fail "--interval-seconds requires a value"
		interval_seconds="$2"
		shift 2
		;;
	--help)
		usage
		exit 0
		;;
	*)
		fail "unknown argument: $1"
		;;
	esac
done

[[ "${listening_confirmed}" == true ]] || fail \
	"open Recording settings and confirm Speech Detection reports Listening"
[[ -n "${input_device}" ]] || fail "--input-device is required"
[[ -n "${output_file}" ]] || fail "--output is required"
[[ "${duration_seconds}" =~ ^[1-9][0-9]*$ ]] || fail "duration must be a positive integer"
[[ "${interval_seconds}" =~ ^[1-9][0-9]*$ ]] || fail "interval must be a positive integer"
((interval_seconds <= duration_seconds)) || fail "interval cannot exceed duration"
[[ -d "${APP_PATH}" ]] || fail "build the default signed bundle first: ${APP_PATH}"
command -v rg >/dev/null || fail "rg is required for the sensitive-log audit"

bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${APP_PATH}/Contents/Info.plist")"
display_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "${APP_PATH}/Contents/Info.plist")"
url_scheme="$(
	/usr/libexec/PlistBuddy \
		-c 'Print :CFBundleURLTypes:0:CFBundleURLSchemes:0' \
		"${APP_PATH}/Contents/Info.plist"
)"
[[ "${bundle_identifier}" == "${EXPECTED_BUNDLE_IDENTIFIER}" ]] || fail \
	"unexpected bundle identifier: ${bundle_identifier}"
[[ "${display_name}" == "${EXPECTED_DISPLAY_NAME}" ]] || fail \
	"unexpected display name: ${display_name}"
[[ "${url_scheme}" == "${EXPECTED_URL_SCHEME}" ]] || fail \
	"unexpected URL scheme: ${url_scheme}"

codesign --verify --deep --strict "${APP_PATH}"
team_identifier="$(
	codesign -dv --verbose=4 "${APP_PATH}" 2>&1 |
		awk -F= '/^TeamIdentifier=/ { print $2; exit }'
)"
[[ "${team_identifier}" == "${EXPECTED_TEAM_IDENTIFIER}" ]] || fail \
	"unexpected signing team: ${team_identifier:-missing}"
"${PACKAGE_ROOT}/Scripts/audit-voice-activity-detection-model.sh" "${APP_PATH}"

app_pid=""
while IFS= read -r candidate_pid; do
	[[ -n "${candidate_pid}" ]] || continue
	candidate_command="$(ps -p "${candidate_pid}" -o command= 2>/dev/null || true)"
	if [[ "${candidate_command}" == "${APP_EXECUTABLE}" ]]; then
		[[ -z "${app_pid}" ]] || fail "more than one Luxel Dev process is running"
		app_pid="${candidate_pid}"
	fi
done < <(pgrep -f "${APP_EXECUTABLE}" || true)
[[ -n "${app_pid}" ]] || fail "relaunch ${APP_PATH} before starting the soak"

temporary_root="${TMPDIR:-/tmp}"
staging_directory="${temporary_root%/}/Luxel/Recordings"
application_support_directory="${HOME}/Library/Application Support/Luxel"

artifact_snapshot() {
	{
		for monitored_directory in \
			"${recordings_directory}" \
			"${staging_directory}" \
			"${application_support_directory}"; do
			if [[ -e "${monitored_directory}" ]]; then
				find "${monitored_directory}" -exec stat -f '%HT %m %z %N' {} +
			else
				printf 'missing %s\n' "${monitored_directory}"
			fi
		done
	} | LC_ALL=C sort | shasum -a 256 | awk '{ print $1 }'
}

output_parent="$(dirname "${output_file}")"
mkdir -p "${output_parent}"
printf 'timestamp,elapsed_seconds,cpu_percent,rss_kib\n' >"${output_file}"

initial_artifact_snapshot="$(artifact_snapshot)"
start_epoch="$(date +%s)"
end_epoch="$((start_epoch + duration_seconds))"
start_iso8601="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

while :; do
	current_epoch="$(date +%s)"
	elapsed_seconds="$((current_epoch - start_epoch))"
	current_command="$(ps -p "${app_pid}" -o command= 2>/dev/null || true)"
	[[ "${current_command}" == "${APP_EXECUTABLE}" ]] || fail \
		"Luxel Dev exited or relaunched during the soak"
	read -r cpu_percent rss_kib < <(ps -p "${app_pid}" -o %cpu=,rss=)
	printf '%s,%s,%s,%s\n' \
		"$(date -u '+%Y-%m-%dT%H:%M:%SZ')" \
		"${elapsed_seconds}" \
		"${cpu_percent}" \
		"${rss_kib}" >>"${output_file}"

	current_artifact_snapshot="$(artifact_snapshot)"
	[[ "${current_artifact_snapshot}" == "${initial_artifact_snapshot}" ]] || fail \
		"recording, staging, history, or transcript artifacts changed before consent"

	((current_epoch >= end_epoch)) && break
	remaining_seconds="$((end_epoch - current_epoch))"
	sleep_seconds="${interval_seconds}"
	((sleep_seconds <= remaining_seconds)) || sleep_seconds="${remaining_seconds}"
	sleep "${sleep_seconds}"
done

average_cpu="$(
	awk -F, 'NR > 1 { total += $3; count += 1 } END { printf "%.3f", total / count }' \
		"${output_file}"
)"
read -r start_rss end_rss maximum_rss monotonic_growth < <(
	awk -F, '
		NR == 2 { start = $4; previous = $4; maximum = $4; monotonic = 1 }
		NR > 2 {
			if ($4 < previous) monotonic = 0
			if ($4 > maximum) maximum = $4
			previous = $4
		}
		END {
			growth = monotonic && previous > start ? "yes" : "no"
			printf "%d %d %d %s\n", start, previous, maximum, growth
		}
	' "${output_file}"
)

sensitive_log_matches="$(
	/usr/bin/log show \
		--start "${start_iso8601}" \
		--style compact \
		--predicate "processIdentifier == ${app_pid}" 2>/dev/null |
		rg -i -c \
			'voice.?detection|speech.?detect|probabilit|microphone.?name|speech.?duration|transcript.?text|/Users/|/tmp/' \
		|| true
)"
sensitive_log_matches="${sensitive_log_matches:-0}"

echo "Voice detection soak completed"
echo "Bundle: ${display_name} (${bundle_identifier}, ${url_scheme})"
echo "Input device: ${input_device}"
echo "Power source: $(pmset -g batt | sed -n '1p')"
echo "Duration seconds: ${duration_seconds}"
echo "Sample interval seconds: ${interval_seconds}"
echo "Average CPU percent: ${average_cpu}"
echo "RSS KiB start/end/max: ${start_rss}/${end_rss}/${maximum_rss}"
echo "Monotonic RSS growth: ${monotonic_growth}"
echo "Artifact snapshot unchanged: yes"
echo "Sensitive detection log matches: ${sensitive_log_matches}"
echo "Samples: ${output_file}"

awk -v average="${average_cpu}" 'BEGIN { exit !(average < 5.0) }' || fail \
	"average CPU ${average_cpu}% is not below 5%"
[[ "${monotonic_growth}" == no ]] || fail "RSS grew monotonically"
[[ "${sensitive_log_matches}" == 0 ]] || fail \
	"sensitive detection data may be present in unified logging"
