#!/usr/bin/env python3

import argparse
import copy
import hashlib
import json
import pathlib
import plistlib
import re
import subprocess
import tempfile


PACKAGE_ROOT = pathlib.Path(__file__).resolve().parent.parent
ARTIFACT_ROOT = PACKAGE_ROOT / "Vendor" / "Artifacts"
MANIFEST_PATH = ARTIFACT_ROOT / "manifest.json"

EXPECTED_BUILD = {
    "platform": "macos",
    "architectures": ["arm64"],
    "minimumOS": "26.0",
    "sdk": "26.5",
    "xcode": "26.6",
    "xcodeBuild": "17F113",
    "appleClang": "Apple clang version 21.0.0 (clang-2100.1.1.101)",
    "cmake": "4.4.2",
    "archiveNormalization": "Apple ranlib -D",
}

EXPECTED_LEDGER_SECTIONS = {
    "libvpx": "330c9ffb7d9583862701c935aa5d112b5695167d3e05ac894908363ff9e61b52",
    "libopus": "1b75cd51123fc725331c0b8b4ac1cab838b4be1fcb27b5f3bd7c249681d48480",
    "svt-av1": "63024f1244fe1cf0b1f198e9a7888ccf42ac1497d684bc51575ce06087d9039a",
    "svt-av1-aom": "9bde790f559fd70d6f74c38e016d0c7b9d1fe7bcc488f50db8813d3077c32864",
    "svt-av1-dav1d": "7eb8009553c91a65b40404a308b24af95be07b4f3dbc7b8455aba8da7a02a6a7",
    "svt-av1-fastfeat": "e3bbcd72c6497c97af289ef4feb39f0cc0d2d34c6c2168f4de82505ab29e4de1",
}

EXPECTED = {
    "libvpx": {
        "version": "1.16.0",
        "tag": "v1.16.0",
        "runtimeVersion": "v1.16.0",
        "source": {
            "url": "https://chromium.googlesource.com/webm/libvpx",
            "tagObject": "04def0a07f8bfa95785e30e6db95036cda17f9b2",
            "commit": "1024874c5919305883187e2953de8fcb4c3d7fa6",
            "tree": "5e48c010122b13fe684e4419d45feee3157d7387",
            "archiveSha256": None,
        },
        "xcframework": "CVPX.xcframework",
        "library": "macos-arm64/libvpx.a",
        "librarySha256": "fa8be9e12a975b2f33e605d092edc33784d571b615b6dbc19647f2d1fed0e27d",
        "libraryBytes": 1568088,
        "headers": "macos-arm64/Headers",
        "headersSha256": "ef4c03480816b908ac3c714da1280af2fb2d44f7892a06ed27771293ab853937",
        "headersBytes": 139933,
        "headerFiles": 10,
        "probe": ("vpx/vpx_codec.h", "vpx_codec_version_str()"),
        "licenses": [
            {
                "id": "libvpx",
                "spdx": "BSD-3-Clause",
                "sourcePath": "LICENSE",
                "sha256": "8267348d5af1262c11d1a08de2f5afc77457755f1ac658627dd9acf71011d615",
                "ledgerDependencyID": "libvpx",
            },
            {
                "id": "libvpx-patents",
                "spdx": "LicenseRef-Google-WebM-Patent-Grant",
                "sourcePath": "PATENTS",
                "sha256": "cc3273e0694ea5896145e0677699b53471b03ea43021ddc50e7923fbb9f5023c",
                "ledgerDependencyID": "libvpx",
            },
        ],
    },
    "libopus": {
        "version": "1.6.1",
        "tag": "v1.6.1",
        "runtimeVersion": "libopus 1.6.1",
        "source": {
            "url": "https://downloads.xiph.org/releases/opus/opus-1.6.1.tar.gz",
            "tagObject": "a5d6c1b6f4e582df97390f9ac5c6e7c51cbffffe",
            "commit": "22244de5a79bd1d6d623c32e72bf1954b56235be",
            "tree": "a5e21b6751d8f187b83ad9d5f3a57aab801cf722",
            "archiveSha256": "6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1",
        },
        "xcframework": "COpus.xcframework",
        "library": "macos-arm64/libopus.a",
        "librarySha256": "35ab58a2020adda1c20e5dad1f74cb37b6803c7b6a2ca08ed9a9bffa60c21062",
        "libraryBytes": 686128,
        "headers": "macos-arm64/Headers",
        "headersSha256": "67d9b2956fc78e4666b88226caa14f95b4eefecaf48fd4b366a83cc34c36a27e",
        "headersBytes": 174535,
        "headerFiles": 6,
        "probe": ("opus/opus.h", "opus_get_version_string()"),
        "licenses": [
            {
                "id": "libopus",
                "spdx": "BSD-3-Clause",
                "sourcePath": "COPYING",
                "sha256": "01e1167d54a096d123cf6dfbbeb19587278845c6481d2d66d545669846079551",
                "ledgerDependencyID": "libopus",
            }
        ],
    },
    "svt-av1": {
        "version": "4.2.0",
        "tag": "v4.2.0",
        "runtimeVersion": "4.2.0",
        "source": {
            "url": "https://gitlab.com/AOMediaCodec/SVT-AV1.git",
            "tagObject": None,
            "commit": "9292ec8e32bce26f781f277ec8739b53426c4300",
            "tree": "1953884a4de4808f941180d1fb1e28587af2e5ff",
            "archiveSha256": None,
        },
        "xcframework": "CSVTAV1.xcframework",
        "library": "macos-arm64/libSvtAv1Enc.a",
        "librarySha256": "d716364b41c3b966700ad035775846e80e06ac3ad9c2426ba83a0ed9c6e22f04",
        "libraryBytes": 5661064,
        "headers": "macos-arm64/Headers",
        "headersSha256": "a343abe8d9dc8f47842f0bac341e1fd327140f819bd538fee5d1bf02e538fbfa",
        "headersBytes": 80966,
        "headerFiles": 8,
        "probe": ("svt-av1/EbSvtAv1Enc.h", "svt_av1_get_version()"),
        "licenses": [
            {
                "id": "svt-av1",
                "spdx": "BSD-3-Clause-Clear",
                "sourcePath": "LICENSE.md",
                "sha256": "0acc2fcb27472bdc9aaf8b71f37055bbdac4f54671b7d922f241bd7fcd0dd3e6",
                "ledgerDependencyID": "svt-av1",
            },
            {
                "id": "svt-av1-aom",
                "spdx": "BSD-2-Clause",
                "sourcePath": "LICENSE-BSD2.md",
                "sha256": "c582fcbeb9cf972a60d298bfaf41dc5adff2dd14208946edcb9bb56a281e8438",
                "ledgerDependencyID": "svt-av1-aom",
            },
            {
                "id": "svt-av1-dav1d-asm",
                "spdx": "BSD-2-Clause",
                "sourcePath": "Source/Lib/ASM_NEON/dav1d_asm.S",
                "sha256": "84419d4760049cf23cd0fc25bfec49bd3f8863f7b4b8de170709d846ba1088e6",
                "ledgerDependencyID": "svt-av1-dav1d",
            },
            {
                "id": "svt-av1-dav1d-util",
                "spdx": "BSD-2-Clause",
                "sourcePath": "Source/Lib/ASM_NEON/dav1d_util.S",
                "sha256": "c78bbab4d58ae7e1cf173376701c660a79bed5e245c5daad94656d087fd93349",
                "ledgerDependencyID": "svt-av1-dav1d",
            },
            {
                "id": "svt-av1-fastfeat",
                "spdx": "BSD-3-Clause",
                "sourcePath": "third_party/fastfeat/LICENSE",
                "sha256": "043dcfd059386f9facd376351b2bd79325778744aa442177390cdfcca54babed",
                "ledgerDependencyID": "svt-av1-fastfeat",
            },
            {
                "id": "svt-av1-patents",
                "spdx": "LicenseRef-AOM-Patent-1.0",
                "sourcePath": "PATENTS.md",
                "sha256": "20678ab10402659106dc4c147c97b2a6e94b5c0695415e15a8f195ebc3547922",
                "ledgerDependencyID": "svt-av1",
            },
        ],
    },
}

SCRIPT_CHECKS = {
    "Scripts/build-luxel-app.sh": [
        'CODEC_LICENSE_CHECKER="${PACKAGE_ROOT}/Scripts/check-codec-licenses.sh"',
        '"${CODEC_LICENSE_CHECKER}"',
    ],
    "Scripts/build-luxel-mas-pkg.sh": [
        'CODEC_LICENSE_CHECKER="${PACKAGE_ROOT}/Scripts/check-codec-licenses.sh"',
        '"${CODEC_LICENSE_CHECKER}"',
    ],
    "Vendor/build-native-codecs.sh": [
        'generate-native-codec-manifest.py" --verify-toolchain-only',
        'generate-native-codec-manifest.py"',
    ],
    "Vendor/build-webm-codecs.sh": [
        'generate-native-codec-manifest.py" --verify-toolchain-only',
        'Scripts/audit-native-codecs.py"',
    ],
    "Vendor/build-libopus.sh": [
        'VERSION="1.6.1"',
        'SHA256="6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1"',
        '-DCMAKE_OSX_SYSROOT="${SDK_PATH}"',
        "-ffile-prefix-map=${SOURCE_DIR}=opus-${VERSION}",
        'xcrun ranlib -D "${INSTALL_DIR}/lib/libopus.a"',
    ],
    "Vendor/build-libvpx.sh": [
        'TAG="v1.16.0"',
        'PEELED_COMMIT="1024874c5919305883187e2953de8fcb4c3d7fa6"',
        'INSTALL_PREFIX="/usr/local"',
        '"../libvpx-${TAG#v}/configure"',
        'DESTDIR="${INSTALL_DIR}" install',
        'xcrun ranlib -D "${INSTALLED_ROOT}/lib/libvpx.a"',
    ],
    "Vendor/build-libsvtav1.sh": [
        'TAG="v4.2.0"',
        'PEELED_COMMIT="9292ec8e32bce26f781f277ec8739b53426c4300"',
        '-DCMAKE_OSX_SYSROOT="${SDK_PATH}"',
        "-ffile-prefix-map=${SOURCE_DIR}=svt-av1-${TAG#v}",
        'xcrun ranlib -D "${INSTALL_DIR}/lib/libSvtAv1Enc.a"',
    ],
}

SCRIPT_FORBIDDEN_TEXT = {
    "Vendor/build-webm-codecs.sh": [
        'generate-native-codec-manifest.py"\n',
    ]
}

EXPECTED_TOOL_VERSIONS = {"cmake": "4.4.2"}


def fail(message: str) -> None:
    raise SystemExit(message)


def run(*command: str) -> str:
    return subprocess.check_output(command, text=True).strip()


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def directory_metadata(root: pathlib.Path) -> dict[str, object]:
    digest = hashlib.sha256()
    byte_size = 0
    file_count = 0
    for child in sorted(path for path in root.rglob("*") if path.is_file()):
        relative_path = child.relative_to(root).as_posix()
        digest.update(relative_path.encode("utf-8"))
        digest.update(b"\0")
        digest.update(bytes.fromhex(sha256(child)))
        byte_size += child.stat().st_size
        file_count += 1
    return {"sha256": digest.hexdigest(), "bytes": byte_size, "files": file_count}


def verify_script_contents(relative_path: str, contents: str) -> None:
    for text in SCRIPT_CHECKS.get(relative_path, []):
        if text not in contents:
            fail(f"Native codec build pin or release gate is missing from {relative_path}: {text}")
    for text in SCRIPT_FORBIDDEN_TEXT.get(relative_path, []):
        if text in contents:
            fail(f"Native codec partial build contains forbidden global provenance generation: {relative_path}")

    if relative_path in ("Scripts/build-luxel-app.sh", "Scripts/build-luxel-mas-pkg.sh"):
        if contents.index('"${CODEC_LICENSE_CHECKER}"') > contents.index("swift build"):
            fail(f"Native codec release gate must run before compilation in {relative_path}.")


def verify_scripts() -> None:
    for relative_path in SCRIPT_CHECKS:
        contents = (PACKAGE_ROOT / relative_path).read_text(encoding="utf-8")
        verify_script_contents(relative_path, contents)

    tool_versions: dict[str, str] = {}
    for line in (PACKAGE_ROOT.parent.parent / ".tool-versions").read_text(encoding="utf-8").splitlines():
        fields = line.split()
        if len(fields) == 2:
            tool_versions[fields[0]] = fields[1]
    verify_tool_versions(tool_versions)


def verify_tool_versions(tool_versions: dict[str, str]) -> None:
    for tool, version in EXPECTED_TOOL_VERSIONS.items():
        if tool_versions.get(tool) != version:
            fail(f"Native codec tool pin mismatch for {tool}: {tool_versions.get(tool)!r}")


def current_build_metadata() -> dict[str, object]:
    xcode_lines = run("xcodebuild", "-version").splitlines()
    return {
        "platform": "macos",
        "architectures": ["arm64"],
        "minimumOS": "26.0",
        "sdk": run("xcrun", "--sdk", "macosx", "--show-sdk-version"),
        "xcode": xcode_lines[0].removeprefix("Xcode "),
        "xcodeBuild": xcode_lines[1].removeprefix("Build version "),
        "appleClang": run("xcrun", "clang", "--version").splitlines()[0],
        "cmake": run("cmake", "--version").splitlines()[0].removeprefix("cmake version "),
        "archiveNormalization": "Apple ranlib -D",
    }


def verify_build(build: dict[str, object], *, verify_installed_toolchain: bool) -> None:
    if build != EXPECTED_BUILD:
        fail("Native codec manifest build toolchain does not match the reviewed toolchain lock.")
    if verify_installed_toolchain and current_build_metadata() != EXPECTED_BUILD:
        fail("Installed native codec build toolchain does not match the reviewed toolchain lock.")


def expected_library_manifest(expected: dict[str, object]) -> dict[str, object]:
    return {
        "relativePath": expected["library"],
        "sha256": expected["librarySha256"],
        "bytes": expected["libraryBytes"],
    }


def expected_headers_manifest(expected: dict[str, object]) -> dict[str, object]:
    return {
        "relativePath": expected["headers"],
        "sha256": expected["headersSha256"],
        "bytes": expected["headersBytes"],
        "files": expected["headerFiles"],
    }


def verify_artifact_manifest(artifact: dict[str, object], expected: dict[str, object]) -> None:
    codec_id = str(artifact.get("id"))
    for key in ("version", "tag", "runtimeVersion", "source", "xcframework"):
        if artifact.get(key) != expected[key]:
            fail(f"Native codec manifest {key} mismatch for {codec_id}.")
    if artifact.get("library") != expected_library_manifest(expected):
        fail(f"Native codec locked library metadata mismatch for {codec_id}.")
    if artifact.get("headers") != expected_headers_manifest(expected):
        fail(f"Native codec locked header metadata mismatch for {codec_id}.")
    if artifact.get("licenses") != expected["licenses"]:
        fail(f"Native codec exact license provenance mismatch for {codec_id}.")


def verify_runtime_version(
    expected: dict[str, object], headers: pathlib.Path, library: pathlib.Path
) -> None:
    include, expression = expected["probe"]
    source = f'#include <stdio.h>\n#include <{include}>\nint main(void){{puts({expression});return 0;}}\n'
    with tempfile.TemporaryDirectory(prefix="luxel-codec-probe-") as temporary_directory:
        temporary_root = pathlib.Path(temporary_directory)
        source_path = temporary_root / ("probe.cc" if expected["version"] == "4.2.0" else "probe.c")
        executable_path = temporary_root / "probe"
        source_path.write_text(source, encoding="utf-8")
        compiler = "clang++" if source_path.suffix == ".cc" else "clang"
        command = ["xcrun", compiler, str(source_path), "-I", str(headers), str(library)]
        if compiler == "clang++":
            command.extend(["-framework", "Accelerate"])
        command.extend(["-o", str(executable_path)])
        subprocess.run(command, check=True, capture_output=True, text=True)
        actual = run(str(executable_path))
    if actual != expected["runtimeVersion"]:
        fail(f"Native codec runtime version mismatch for {expected['xcframework']}: {actual}")


def verify_artifact(artifact: dict[str, object], build: dict[str, object]) -> None:
    codec_id = str(artifact.get("id"))
    expected = EXPECTED.get(codec_id)
    if expected is None:
        fail(f"Unexpected native codec manifest entry: {codec_id}")
    verify_artifact_manifest(artifact, expected)

    xcframework = ARTIFACT_ROOT / str(expected["xcframework"])
    library = xcframework / str(expected["library"])
    headers = xcframework / str(expected["headers"])
    if not library.is_file() or not headers.is_dir():
        fail(f"Native codec artifact is missing for {codec_id}.")

    if sha256(library) != expected["librarySha256"]:
        fail(f"Native codec library checksum does not match its reviewed lock for {codec_id}.")
    if library.stat().st_size != expected["libraryBytes"]:
        fail(f"Native codec library byte count does not match its reviewed lock for {codec_id}.")

    header_metadata = directory_metadata(headers)
    if header_metadata != {
        "sha256": expected["headersSha256"],
        "bytes": expected["headersBytes"],
        "files": expected["headerFiles"],
    }:
        fail(f"Native codec headers do not match their reviewed lock for {codec_id}.")

    info = plistlib.loads((xcframework / "Info.plist").read_bytes())
    expected_library = {
        "LibraryIdentifier": "macos-arm64",
        "LibraryPath": library.name,
        "BinaryPath": library.name,
        "HeadersPath": "Headers",
        "SupportedArchitectures": ["arm64"],
        "SupportedPlatform": "macos",
    }
    if info.get("AvailableLibraries") != [expected_library]:
        fail(f"Native codec XCFramework slice manifest mismatch for {codec_id}.")
    if info.get("CFBundlePackageType") != "XFWK" or info.get("XCFrameworkFormatVersion") != "1.0":
        fail(f"Native codec XCFramework metadata mismatch for {codec_id}.")

    if run("xcrun", "lipo", "-archs", str(library)) != "arm64":
        fail(f"Native codec archive architecture mismatch for {codec_id}.")
    load_commands = run("xcrun", "otool", "-l", str(library))
    minimum_version_entries = re.findall(r"\bminos\s+(\S+)", load_commands)
    sdk_version_entries = re.findall(r"\bsdk\s+(\S+)", load_commands)
    archive_listing = run("ar", "-tv", str(library)).splitlines()
    archive_members = run("ar", "-t", str(library)).splitlines()
    object_count = sum(member.endswith(".o") for member in archive_members)
    if object_count == 0 or len(minimum_version_entries) != object_count:
        fail(f"Native codec deployment metadata is incomplete for {codec_id}.")
    if len(sdk_version_entries) != object_count:
        fail(f"Native codec SDK metadata is incomplete for {codec_id}.")
    minimum_versions = set(minimum_version_entries)
    sdk_versions = set(sdk_version_entries)
    if minimum_versions != {build["minimumOS"]}:
        fail(f"Native codec deployment target mismatch for {codec_id}: {minimum_versions}")
    if sdk_versions - {"n/a"} != {build["sdk"]}:
        fail(f"Native codec SDK mismatch for {codec_id}: {sdk_versions}")

    if not archive_listing or any(re.search(r"\s0/0\s", line) is None for line in archive_listing):
        fail(f"Native codec archive metadata is not normalized for {codec_id}.")
    embedded_strings = run("strings", str(library))
    if re.search(r"/(?:Users|tmp|private/var)/", embedded_strings):
        fail(f"Native codec archive contains an absolute checkout path for {codec_id}.")
    if expected["runtimeVersion"] not in embedded_strings:
        fail(f"Native codec archive does not contain its expected version for {codec_id}.")
    verify_runtime_version(expected, headers, library)

    print(
        f"Verified {codec_id} {expected['version']}: "
        f"{library.stat().st_size} bytes, SHA-256 {sha256(library)}"
    )


def verify_ledger(ledger: str, artifacts: list[dict[str, object]]) -> None:
    ledger_ids = {
        entry["ledgerDependencyID"]
        for artifact in artifacts
        for entry in artifact.get("licenses", [])
    }
    if ledger_ids != set(EXPECTED_LEDGER_SECTIONS):
        fail("Native codec manifest-to-ledger dependency mapping is incomplete.")

    for dependency_id, expected_hash in EXPECTED_LEDGER_SECTIONS.items():
        match = re.search(
            rf"^## Dependency: {re.escape(dependency_id)}\n.*?(?=^## |\Z)",
            ledger,
            flags=re.MULTILINE | re.DOTALL,
        )
        if match is None:
            fail(f"Native codec license ledger entry is missing: {dependency_id}")
        actual_hash = hashlib.sha256(match.group(0).encode("utf-8")).hexdigest()
        if actual_hash != expected_hash:
            fail(f"Native codec canonical license notice mismatch: {dependency_id}")


def load_manifest() -> dict[str, object]:
    if not MANIFEST_PATH.is_file():
        fail(f"Native codec manifest is missing: {MANIFEST_PATH}")
    return json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))


def verify_manifest(manifest: dict[str, object], *, verify_installed_toolchain: bool) -> None:
    if manifest.get("schemaVersion") != 1:
        fail("Native codec manifest schema version is unsupported.")
    build = manifest.get("build", {})
    verify_build(build, verify_installed_toolchain=verify_installed_toolchain)
    artifacts = manifest.get("artifacts", [])
    if [artifact.get("id") for artifact in artifacts] != list(EXPECTED):
        fail("Native codec manifest inventory is incomplete or out of order.")
    for artifact in artifacts:
        verify_artifact_manifest(artifact, EXPECTED[str(artifact["id"])])


def expect_self_test_failure(operation, description: str) -> None:
    try:
        operation()
    except SystemExit:
        return
    fail(f"Native codec auditor self-test failed to reject {description}.")


def run_self_tests(manifest: dict[str, object], ledger: str) -> None:
    changed_build = copy.deepcopy(manifest["build"])
    changed_build["cmake"] = "4.4.3"
    expect_self_test_failure(
        lambda: verify_build(changed_build, verify_installed_toolchain=False),
        "toolchain drift",
    )

    changed_tool_versions = dict(EXPECTED_TOOL_VERSIONS)
    changed_tool_versions["cmake"] = "4.4.3"
    expect_self_test_failure(
        lambda: verify_tool_versions(changed_tool_versions),
        "tool pin drift",
    )

    original_artifact = manifest["artifacts"][0]
    expected_artifact = EXPECTED[str(original_artifact["id"])]
    for field in ("sha256", "bytes"):
        changed_artifact = copy.deepcopy(original_artifact)
        changed_artifact["library"][field] = "changed" if field == "sha256" else 0
        expect_self_test_failure(
            lambda changed=changed_artifact: verify_artifact_manifest(changed, expected_artifact),
            f"library {field} drift",
        )
    for field in ("sha256", "bytes", "files"):
        changed_artifact = copy.deepcopy(original_artifact)
        changed_artifact["headers"][field] = "changed" if field == "sha256" else 0
        expect_self_test_failure(
            lambda changed=changed_artifact: verify_artifact_manifest(changed, expected_artifact),
            f"header {field} drift",
        )
    for field in ("id", "spdx", "sourcePath", "sha256", "ledgerDependencyID"):
        changed_artifact = copy.deepcopy(original_artifact)
        changed_artifact["licenses"][0][field] = "changed"
        expect_self_test_failure(
            lambda changed=changed_artifact: verify_artifact_manifest(changed, expected_artifact),
            f"license {field} drift",
        )

    changed_ledger = ledger.replace("Name: libvpx", "Name: replaced", 1)
    expect_self_test_failure(
        lambda: verify_ledger(changed_ledger, manifest["artifacts"]),
        "canonical license notice replacement",
    )

    for relative_path in ("Scripts/build-luxel-app.sh", "Scripts/build-luxel-mas-pkg.sh"):
        contents = (PACKAGE_ROOT / relative_path).read_text(encoding="utf-8")
        changed_contents = contents.replace('"${CODEC_LICENSE_CHECKER}"\n', "", 1)
        expect_self_test_failure(
            lambda path=relative_path, changed=changed_contents: verify_script_contents(path, changed),
            f"release-build codec gate removal from {relative_path}",
        )

    webm_script = "Vendor/build-webm-codecs.sh"
    webm_contents = (PACKAGE_ROOT / webm_script).read_text(encoding="utf-8")
    changed_webm_contents = webm_contents + '/usr/bin/python3 "generate-native-codec-manifest.py"\n'
    expect_self_test_failure(
        lambda: verify_script_contents(webm_script, changed_webm_contents),
        "partial-build global manifest generation",
    )
    print("Native codec auditor negative self-tests passed.")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    arguments = parser.parse_args()

    manifest = load_manifest()
    ledger = (PACKAGE_ROOT / "THIRD_PARTY_LICENSES.md").read_text(encoding="utf-8")
    verify_manifest(manifest, verify_installed_toolchain=True)
    verify_scripts()
    verify_ledger(ledger, manifest["artifacts"])
    if arguments.self_test:
        run_self_tests(manifest, ledger)
    for artifact in manifest["artifacts"]:
        verify_artifact(artifact, manifest["build"])

    print("Native codec artifacts, provenance, deployment targets, runtime versions, and licenses are valid.")


if __name__ == "__main__":
    main()
