#!/usr/bin/env bash
set -euo pipefail

VERSION="1.6.1"
ARCH="arm64"
DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-26.0}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${ROOT}/.build/vendor"
TARBALL="${WORK_DIR}/opus-${VERSION}.tar.gz"
SOURCE_DIR="${WORK_DIR}/opus-${VERSION}"
BUILD_DIR="${WORK_DIR}/opus-build"
INSTALL_DIR="${WORK_DIR}/opus-install"
HEADERS_DIR="${WORK_DIR}/opus-xcframework-headers"
ARTIFACT="${ROOT}/Vendor/Artifacts/COpus.xcframework"
URL="https://downloads.xiph.org/releases/opus/opus-${VERSION}.tar.gz"
SHA256="6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1"

mkdir -p "${WORK_DIR}" "${ROOT}/Vendor/Artifacts"

if [[ ! -f "${TARBALL}" ]]; then
	curl -L --fail --silent --show-error "${URL}" -o "${TARBALL}"
fi

printf "%s  %s\n" "${SHA256}" "${TARBALL}" | shasum -a 256 -c -

rm -rf "${SOURCE_DIR}" "${BUILD_DIR}" "${INSTALL_DIR}" "${HEADERS_DIR}" "${ARTIFACT}"
tar -xf "${TARBALL}" -C "${WORK_DIR}"

cmake \
	-S "${SOURCE_DIR}" \
	-B "${BUILD_DIR}" \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_OSX_ARCHITECTURES="${ARCH}" \
	-DCMAKE_OSX_DEPLOYMENT_TARGET="${DEPLOYMENT_TARGET}" \
	-DOPUS_BUILD_PROGRAMS=OFF \
	-DOPUS_BUILD_TESTING=OFF \
	-DOPUS_INSTALL_PKG_CONFIG_MODULE=OFF \
	-DBUILD_SHARED_LIBS=OFF \
	-DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}"

cmake --build "${BUILD_DIR}" --config Release --target install

mkdir -p "${HEADERS_DIR}"
cp -R "${INSTALL_DIR}/include/opus" "${HEADERS_DIR}/opus"
cat >"${HEADERS_DIR}/module.modulemap" <<'MODULEMAP'
module COpus {
    umbrella "opus"
    export *
}
MODULEMAP

xcodebuild \
	-create-xcframework \
	-library "${INSTALL_DIR}/lib/libopus.a" \
	-headers "${HEADERS_DIR}" \
	-output "${ARTIFACT}"
