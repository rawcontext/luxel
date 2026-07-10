#!/usr/bin/env bash
set -euo pipefail

unset PYTHONPATH

TOOLS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_ROOT="$(cd "${TOOLS_ROOT}/.." && pwd)"
WORK_ROOT="${MODNET_WORK_ROOT:-${TMPDIR:-/tmp}/luxel-modnet-conversion}"
PYTHON="${PYTHON:-python3.13}"
UPSTREAM_COMMIT="28165a451e4610c9d77cfdf925a94610bb2810fb"
CHECKPOINT_URL="https://drive.usercontent.google.com/download?id=1Nf1ZxeJZJL8Qx9KadcYYyEmmlKhTADxX&export=download&confirm=t"
CHECKPOINT_SHA256="913b82b66558db39b6286c150f809017d7528c872b156eb14333c9c6cb52108b"

if [[ "$(${PYTHON} -c 'import platform; print(platform.python_version())')" != "3.13.13" ]]; then
	echo "MODNet conversion requires Python 3.13.13." >&2
	exit 1
fi

mkdir -p "${WORK_ROOT}"
if [[ ! -d "${WORK_ROOT}/MODNet/.git" ]]; then
	git clone https://github.com/ZHKKKe/MODNet.git "${WORK_ROOT}/MODNet"
fi
git -C "${WORK_ROOT}/MODNet" fetch --depth 1 origin "${UPSTREAM_COMMIT}"
git -C "${WORK_ROOT}/MODNet" checkout --detach "${UPSTREAM_COMMIT}"

if [[ ! -f "${WORK_ROOT}/modnet_webcam_portrait_matting.ckpt" ]]; then
	curl -fL "${CHECKPOINT_URL}" -o "${WORK_ROOT}/modnet_webcam_portrait_matting.ckpt"
fi
echo "${CHECKPOINT_SHA256}  ${WORK_ROOT}/modnet_webcam_portrait_matting.ckpt" | shasum -a 256 -c -

if [[ ! -x "${WORK_ROOT}/venv/bin/python" ]]; then
	"${PYTHON}" -m venv "${WORK_ROOT}/venv"
fi
"${WORK_ROOT}/venv/bin/python" -m pip install --requirement "${TOOLS_ROOT}/requirements.lock"

rm -rf "${MODELS_ROOT}/modnet/MODNetPortraitMatting.mlmodelc"
"${WORK_ROOT}/venv/bin/python" "${TOOLS_ROOT}/convert_modnet.py" \
	--upstream "${WORK_ROOT}/MODNet" \
	--checkpoint "${WORK_ROOT}/modnet_webcam_portrait_matting.ckpt" \
	--output "${MODELS_ROOT}/modnet" \
	--fixtures "${TOOLS_ROOT}/Fixtures"
