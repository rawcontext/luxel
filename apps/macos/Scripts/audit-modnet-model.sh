#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ne 1 ]]; then
	echo "Usage: $0 <modnet-directory|app-bundle|package>" >&2
	exit 2
fi

INPUT_PATH="$1"
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

if [[ "${INPUT_PATH}" == *.pkg ]]; then
	TEMPORARY_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/luxel-modnet-pkg.XXXXXX")"
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
	MODEL_DIRECTORY="${INPUT_PATH}/Contents/Resources/Models/modnet"
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
        raise SystemExit(f"Required MODNet resource is missing: {required}")

manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
artifact = manifest.get("artifact", {})
compiled = root / artifact.get("directory", "")
if not compiled.is_dir() or compiled.name != "MODNetPortraitMatting.mlmodelc":
    raise SystemExit(f"Required compiled MODNet model is missing: {compiled}")

digest = hashlib.sha256()
byte_size = 0
for child in sorted(candidate for candidate in compiled.rglob("*") if candidate.is_file()):
    relative_path = child.relative_to(compiled).as_posix()
    file_digest = hashlib.sha256(child.read_bytes()).digest()
    digest.update(relative_path.encode("utf-8"))
    digest.update(b"\0")
    digest.update(file_digest)
    byte_size += child.stat().st_size

if digest.hexdigest() != artifact.get("sha256"):
    raise SystemExit("Compiled MODNet model checksum does not match model-manifest.json.")
if byte_size != artifact.get("byteSize"):
    raise SystemExit("Compiled MODNet model size does not match model-manifest.json.")

checkpoint = manifest.get("checkpoint", {})
conversion = manifest.get("conversion", {})
contract = manifest.get("contract", {})
if checkpoint.get("sha256") != "913b82b66558db39b6286c150f809017d7528c872b156eb14333c9c6cb52108b":
    raise SystemExit("MODNet checkpoint provenance is missing or unexpected.")
if conversion.get("minimumDeploymentTarget") != "macOS 26":
    raise SystemExit("MODNet deployment target is missing or unexpected.")
if contract.get("input", {}).get("name") != "cameraImage":
    raise SystemExit("MODNet input contract is missing or unexpected.")
if contract.get("output", {}).get("name") != "alphaMatte":
    raise SystemExit("MODNet output contract is missing or unexpected.")

print(f"Verified MODNet model: {byte_size} bytes, SHA-256 {digest.hexdigest()}")
PY
