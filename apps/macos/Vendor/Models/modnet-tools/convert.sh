#!/usr/bin/env bash
set -euo pipefail

unset PYTHONPATH
unset UV_NO_VERIFY_HASHES
export PYTHONHASHSEED=0

TOOLS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_ROOT="$(cd "${TOOLS_ROOT}/.." && pwd)"
WORK_ROOT="${MODNET_WORK_ROOT:-${TMPDIR:-/tmp}/luxel-modnet-conversion}"
PYTHON="${PYTHON:-python3.13}"
UV="${UV:-uv}"
UPSTREAM_COMMIT="28165a451e4610c9d77cfdf925a94610bb2810fb"
CHECKPOINT_URL="https://drive.usercontent.google.com/download?id=1Nf1ZxeJZJL8Qx9KadcYYyEmmlKhTADxX&export=download&confirm=t"
CHECKPOINT_SHA256="913b82b66558db39b6286c150f809017d7528c872b156eb14333c9c6cb52108b"
EXPECTED_XCODE_OUTPUT=$'Xcode 26.6\nBuild version 17F113'
COREMLCOMPILER_SHA256="ea1cd3a446a1d38d2bae94501d274fc9cf395db865f8ad600573b381e408d85d"
MODEL_ARTIFACTS=(
	"analytics/coremldata.bin"
	"coremldata.bin"
	"metadata.json"
	"model.mil"
	"weights/weight.bin"
)
SOURCE_ARTIFACTS=(
	"metadata.json"
	"model.mil"
	"weights/weight.bin"
)

if [[ "$(${PYTHON} -c 'import platform; print(platform.python_version())')" != "3.13.15" ]]; then
	echo "MODNet conversion requires Python 3.13.15." >&2
	exit 1
fi
case "$(${UV} --version)" in
	"uv 0.12.5" | "uv 0.12.5 "*) ;;
	*)
		echo "MODNet conversion requires uv 0.12.5." >&2
		exit 1
		;;
esac
if [[ "$(/usr/bin/xcodebuild -version)" != "${EXPECTED_XCODE_OUTPUT}" ]]; then
	echo "MODNet conversion requires Xcode 26.6 build 17F113." >&2
	exit 1
fi
COREMLCOMPILER="$(/usr/bin/xcrun --find coremlcompiler)"
if [[ ! -x "${COREMLCOMPILER}" ]] || \
	[[ "$(/usr/bin/shasum -a 256 "${COREMLCOMPILER}" | /usr/bin/awk '{print $1}')" != "${COREMLCOMPILER_SHA256}" ]]; then
	echo "MODNet conversion requires the pinned Xcode 26.6 coremlcompiler." >&2
	exit 1
fi

mkdir -p "${WORK_ROOT}"
WORK_ROOT="$(cd "${WORK_ROOT}" && pwd -P)"
RUN_ROOT="$(mktemp -d "${WORK_ROOT}/run.XXXXXX")"
UPSTREAM_ROOT="${RUN_ROOT}/MODNet"
VENV_ROOT="${RUN_ROOT}/venv"
GENERATED_MODELS_ROOT="${RUN_ROOT}/generated-models"
trap 'rm -rf "${RUN_ROOT}"' EXIT

/usr/bin/git -c core.hooksPath=/dev/null init --quiet "${UPSTREAM_ROOT}"
/usr/bin/git -C "${UPSTREAM_ROOT}" remote add origin https://github.com/ZHKKKe/MODNet.git
/usr/bin/git -c core.hooksPath=/dev/null -C "${UPSTREAM_ROOT}" \
	fetch --quiet --depth 1 --no-tags origin "${UPSTREAM_COMMIT}"
/usr/bin/git -c core.hooksPath=/dev/null -C "${UPSTREAM_ROOT}" \
	checkout --quiet --detach FETCH_HEAD
if [[ "$(/usr/bin/git -C "${UPSTREAM_ROOT}" rev-parse HEAD)" != "${UPSTREAM_COMMIT}" ]] || \
	[[ -n "$(/usr/bin/git -C "${UPSTREAM_ROOT}" status --porcelain=v1 --untracked-files=all)" ]]; then
	echo "MODNet upstream checkout is not pristine at the pinned commit." >&2
	exit 1
fi

CHECKPOINT_PATH="${WORK_ROOT}/modnet_webcam_portrait_matting.ckpt"
if [[ ! -f "${CHECKPOINT_PATH}" ]]; then
	CHECKPOINT_DOWNLOAD="${RUN_ROOT}/modnet_webcam_portrait_matting.ckpt"
	/usr/bin/curl -fL "${CHECKPOINT_URL}" -o "${CHECKPOINT_DOWNLOAD}"
	echo "${CHECKPOINT_SHA256}  ${CHECKPOINT_DOWNLOAD}" | /usr/bin/shasum -a 256 -c -
	mv "${CHECKPOINT_DOWNLOAD}" "${CHECKPOINT_PATH}"
fi
echo "${CHECKPOINT_SHA256}  ${CHECKPOINT_PATH}" | /usr/bin/shasum -a 256 -c -

"${UV}" venv --python "${PYTHON}" "${VENV_ROOT}"
"${UV}" pip sync \
	--python "${VENV_ROOT}/bin/python" \
	--require-hashes \
	--strict \
	"${TOOLS_ROOT}/requirements.lock"

mkdir -p "${GENERATED_MODELS_ROOT}"
	"${VENV_ROOT}/bin/python" "${TOOLS_ROOT}/convert_modnet.py" \
	--upstream "${UPSTREAM_ROOT}" \
	--checkpoint "${CHECKPOINT_PATH}" \
	--output "${GENERATED_MODELS_ROOT}" \
	--coremlcompiler "${COREMLCOMPILER}"

GENERATED_MODEL="${GENERATED_MODELS_ROOT}/MODNetPortraitMatting.mlmodelc"
VENDORED_MODEL="${MODELS_ROOT}/modnet/MODNetPortraitMatting.mlmodelc"

model_file_set_is_valid() {
	local model_root="$1"
	local artifact
	local file_count

	[[ -d "${model_root}" && ! -L "${model_root}" ]] || return 1
	if [[ -n "$(/usr/bin/find "${model_root}" -type l -print -quit)" ]]; then
		return 1
	fi
	for artifact in "${MODEL_ARTIFACTS[@]}"; do
		[[ -f "${model_root}/${artifact}" && ! -L "${model_root}/${artifact}" ]] || return 1
	done
	file_count="$(/usr/bin/find "${model_root}" -type f | /usr/bin/wc -l | /usr/bin/tr -d ' ')"
	[[ "${file_count}" == "${#MODEL_ARTIFACTS[@]}" ]]
}

if ! model_file_set_is_valid "${GENERATED_MODEL}"; then
	echo "Generated MODNet model has an unexpected file set." >&2
	exit 1
fi

REPLACE_VENDORED_MODEL=false
if ! model_file_set_is_valid "${VENDORED_MODEL}"; then
	REPLACE_VENDORED_MODEL=true
else
	SOURCE_CONTENT_CHANGED=false
	COMPILED_CONTENT_CHANGED=false
	for artifact in "${SOURCE_ARTIFACTS[@]}"; do
		if ! /usr/bin/cmp -s "${GENERATED_MODEL}/${artifact}" "${VENDORED_MODEL}/${artifact}"; then
			SOURCE_CONTENT_CHANGED=true
		fi
	done
	for artifact in "${MODEL_ARTIFACTS[@]}"; do
		if ! /usr/bin/cmp -s "${GENERATED_MODEL}/${artifact}" "${VENDORED_MODEL}/${artifact}"; then
			COMPILED_CONTENT_CHANGED=true
		fi
	done

	if [[ "${SOURCE_CONTENT_CHANGED}" == true ]]; then
		REPLACE_VENDORED_MODEL=true
	elif [[ "${COMPILED_CONTENT_CHANGED}" == true ]]; then
		if "${VENV_ROOT}/bin/python" - \
			"${MODELS_ROOT}/modnet/model-manifest.json" \
			"${COREMLCOMPILER_SHA256}" <<'PY'
import json
import pathlib
import sys

manifest = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
conversion = manifest.get("conversion", {})
if conversion.get("xcode") != "26.6":
    raise SystemExit(1)
if conversion.get("xcodeBuild") != "17F113":
    raise SystemExit(1)
if conversion.get("coremlcompilerSha256") != sys.argv[2]:
    raise SystemExit(1)
PY
		then
			if "${VENV_ROOT}/bin/python" "${TOOLS_ROOT}/convert_modnet.py" \
				--upstream "${UPSTREAM_ROOT}" \
				--checkpoint "${CHECKPOINT_PATH}" \
				--validate-compiled "${VENDORED_MODEL}"; then
				echo "Retaining byte-different MODNet compiler output after exact-bundle validation."
			else
				REPLACE_VENDORED_MODEL=true
			fi
		else
			REPLACE_VENDORED_MODEL=true
		fi
	fi
fi

if [[ "${REPLACE_VENDORED_MODEL}" == true ]]; then
	rm -rf "${VENDORED_MODEL}"
	cp -R "${GENERATED_MODEL}" "${VENDORED_MODEL}"
fi
"${VENV_ROOT}/bin/python" - \
	"${GENERATED_MODELS_ROOT}/model-manifest.json" \
	"${VENDORED_MODEL}" <<'PY'
import hashlib
import json
import pathlib
import sys

manifest_path = pathlib.Path(sys.argv[1])
model_path = pathlib.Path(sys.argv[2])
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
digest = hashlib.sha256()
byte_size = 0
files = {}
for child in sorted(path for path in model_path.rglob("*") if path.is_file()):
    relative_path = child.relative_to(model_path).as_posix()
    file_digest = hashlib.sha256(child.read_bytes())
    digest.update(relative_path.encode("utf-8"))
    digest.update(b"\0")
    digest.update(file_digest.digest())
    byte_size += child.stat().st_size
    files[relative_path] = file_digest.hexdigest()
manifest["artifact"]["sha256"] = digest.hexdigest()
manifest["artifact"]["byteSize"] = byte_size
manifest["artifact"]["files"] = files
manifest_path.write_text(
    json.dumps(manifest, indent=2, sort_keys=True) + "\n",
    encoding="utf-8",
)
PY
cp "${GENERATED_MODELS_ROOT}/model-manifest.json" "${MODELS_ROOT}/modnet/model-manifest.json"
