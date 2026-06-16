#!/usr/bin/env bash
set -euo pipefail

TAG="v1.16.0"
PEELED_COMMIT="1024874c5919305883187e2953de8fcb4c3d7fa6"
ARCH_TARGET="arm64-darwin25-gcc"
DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-26.0}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${ROOT}/.build/vendor"
SOURCE_DIR="${WORK_DIR}/libvpx-${TAG#v}"
BUILD_DIR="${WORK_DIR}/libvpx-build"
INSTALL_DIR="${WORK_DIR}/libvpx-install"
HEADERS_DIR="${WORK_DIR}/libvpx-xcframework-headers"
ARTIFACT="${ROOT}/Vendor/Artifacts/CVPX.xcframework"
REPO_URL="https://chromium.googlesource.com/webm/libvpx"

mkdir -p "${WORK_DIR}" "${ROOT}/Vendor/Artifacts"
rm -rf "${SOURCE_DIR}" "${BUILD_DIR}" "${INSTALL_DIR}" "${HEADERS_DIR}" "${ARTIFACT}"

git clone --depth 1 --branch "${TAG}" "${REPO_URL}" "${SOURCE_DIR}"

ACTUAL_COMMIT="$(git -C "${SOURCE_DIR}" rev-parse HEAD)"
if [[ "${ACTUAL_COMMIT}" != "${PEELED_COMMIT}" ]]; then
	echo "libvpx ${TAG} resolved to ${ACTUAL_COMMIT}, expected ${PEELED_COMMIT}." >&2
	exit 1
fi

mkdir -p "${BUILD_DIR}"
(
	cd "${BUILD_DIR}"
	MACOSX_DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET}" "${SOURCE_DIR}/configure" \
		--target="${ARCH_TARGET}" \
		--prefix="${INSTALL_DIR}" \
		--extra-cflags="-mmacosx-version-min=${DEPLOYMENT_TARGET}" \
		--extra-cxxflags="-mmacosx-version-min=${DEPLOYMENT_TARGET}" \
		--enable-pic \
		--disable-examples \
		--disable-tools \
		--disable-docs \
		--disable-unit-tests \
		--disable-vp8 \
		--disable-vp9-decoder \
		--enable-vp9-encoder \
		--disable-shared \
		--enable-static \
		--disable-install-bins \
		--disable-install-docs
)

MACOSX_DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET}" make -C "${BUILD_DIR}" -j"$(sysctl -n hw.ncpu)" install

mkdir -p "${HEADERS_DIR}"
cp -R "${INSTALL_DIR}/include/vpx" "${HEADERS_DIR}/vpx"
cat >"${HEADERS_DIR}/module.modulemap" <<'MODULEMAP'
module CVPX {
    umbrella "vpx"
    export *
}
MODULEMAP

xcodebuild \
	-create-xcframework \
	-library "${INSTALL_DIR}/lib/libvpx.a" \
	-headers "${HEADERS_DIR}" \
	-output "${ARTIFACT}"
