#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
	echo "Usage: $0 <voice-activity-detection-directory|app-bundle|package>" >&2
	exit 2
fi

INPUT_PATH="$1"
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

if [[ "${INPUT_PATH}" == *.pkg ]]; then
	TEMPORARY_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/luxel-vad-pkg.XXXXXX")"
	EXPANDED_PATH="${TEMPORARY_DIRECTORY}/expanded"
	trap 'rm -rf "${TEMPORARY_DIRECTORY}"' EXIT
	pkgutil --expand-full "${INPUT_PATH}" "${EXPANDED_PATH}" >/dev/null
	APP_PATH="$(find "${EXPANDED_PATH}" -type d -name 'Luxel.app' -print -quit)"
	if [[ -z "${APP_PATH}" ]]; then
		echo "Luxel.app was not found in ${INPUT_PATH}." >&2
		exit 1
	fi
	"${SCRIPT_PATH}" "${APP_PATH}"
	exit 0
fi

if [[ "${INPUT_PATH}" == *.app ]]; then
	MODEL_DIRECTORY="${INPUT_PATH}/Contents/Resources/Models/voice-activity-detection"
else
	MODEL_DIRECTORY="${INPUT_PATH}"
fi

python3 - "${MODEL_DIRECTORY}" <<'PY'
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
manifest_path = root / "model-manifest.json"
license_path = root / "LICENSE.txt"
notice_path = root / "NOTICE.md"

for required in (manifest_path, license_path, notice_path):
    if not required.is_file():
        raise SystemExit(f"Required voice activity detection resource is missing: {required}")

manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
artifact = manifest.get("artifact", {})
compiled = root / artifact.get("directory", "")
expected_name = "silero-vad-unified-256ms-v6.2.1.mlmodelc"
if not compiled.is_dir() or compiled.name != expected_name:
    raise SystemExit(f"Required compiled voice activity detection model is missing: {compiled}")

expected_files = artifact.get("files", {})
actual_files = {
    path.relative_to(compiled).as_posix(): path
    for path in compiled.rglob("*")
    if path.is_file()
}
if set(actual_files) != set(expected_files):
    raise SystemExit("Voice activity detection model file set does not match model-manifest.json.")

digest = hashlib.sha256()
byte_size = 0
for relative_path, child in sorted(actual_files.items()):
    file_digest = hashlib.sha256(child.read_bytes())
    if file_digest.hexdigest() != expected_files[relative_path]:
        raise SystemExit(f"Voice activity detection model checksum mismatch: {relative_path}")
    digest.update(relative_path.encode("utf-8"))
    digest.update(b"\0")
    digest.update(file_digest.digest())
    byte_size += child.stat().st_size

if digest.hexdigest() != artifact.get("sha256"):
    raise SystemExit("Compiled voice activity detection model checksum does not match manifest.")
if byte_size != artifact.get("byteSize"):
    raise SystemExit("Compiled voice activity detection model size does not match manifest.")

upstream = manifest.get("upstream", {})
contract = manifest.get("contract", {})
if upstream.get("revision") != "b419383c55c110e2c9271fa6ee0ea83d03c70d96":
    raise SystemExit("Voice activity detection model revision is missing or unexpected.")
if manifest.get("modelVersion") != "6.2.1" or manifest.get("license") != "MIT":
    raise SystemExit("Voice activity detection model identity is missing or unexpected.")
if contract.get("sampleRate") != 16000 or contract.get("audioInputSamples") != 4096:
    raise SystemExit("Voice activity detection model input contract is missing or unexpected.")

print(f"Verified voice activity detection model: {byte_size} bytes, SHA-256 {digest.hexdigest()}")
PY
