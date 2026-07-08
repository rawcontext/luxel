#!/usr/bin/env bash
set -euo pipefail

TAG="v4.1.0"
PEELED_COMMIT="c04f951541ad600e0d9c10836f2ab7b9bc69816d"
ARCH="arm64"
DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-26.0}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${ROOT}/.build/vendor"
SOURCE_DIR="${WORK_DIR}/svt-av1-${TAG#v}"
BUILD_DIR="${WORK_DIR}/svt-av1-build"
INSTALL_DIR="${WORK_DIR}/svt-av1-install"
HEADERS_DIR="${WORK_DIR}/svt-av1-xcframework-headers"
ARTIFACT="${ROOT}/Vendor/Artifacts/CSVTAV1.xcframework"
REPO_URL="https://gitlab.com/AOMediaCodec/SVT-AV1.git"

mkdir -p "${WORK_DIR}" "${ROOT}/Vendor/Artifacts"
rm -rf "${SOURCE_DIR}" "${BUILD_DIR}" "${INSTALL_DIR}" "${HEADERS_DIR}" "${ARTIFACT}"

git clone --depth 1 --branch "${TAG}" "${REPO_URL}" "${SOURCE_DIR}"

ACTUAL_COMMIT="$(git -C "${SOURCE_DIR}" rev-parse HEAD)"
if [[ "${ACTUAL_COMMIT}" != "${PEELED_COMMIT}" ]]; then
	echo "SVT-AV1 ${TAG} resolved to ${ACTUAL_COMMIT}, expected ${PEELED_COMMIT}." >&2
	exit 1
fi

cmake \
	-S "${SOURCE_DIR}" \
	-B "${BUILD_DIR}" \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_OSX_ARCHITECTURES="${ARCH}" \
	-DCMAKE_OSX_DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET}" \
	-DBUILD_SHARED_LIBS=OFF \
	-DBUILD_APPS=OFF \
	-DBUILD_TESTING=OFF \
	-DSVT_AV1_LTO=OFF \
	-DNATIVE=OFF \
	-DEXCLUDE_HASH=ON \
	-DREPRODUCIBLE_BUILDS=ON \
	-DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}"

cmake --build "${BUILD_DIR}" --config Release --target install -j"$(sysctl -n hw.ncpu)"

mkdir -p "${HEADERS_DIR}"
cp -R "${INSTALL_DIR}/include/svt-av1" "${HEADERS_DIR}/svt-av1"
cat >"${HEADERS_DIR}/module.modulemap" <<'MODULEMAP'
module CSVTAV1 {
    umbrella "svt-av1"
    export *
}
MODULEMAP

xcodebuild \
	-create-xcframework \
	-library "${INSTALL_DIR}/lib/libSvtAv1Enc.a" \
	-headers "${HEADERS_DIR}" \
	-output "${ARTIFACT}"
