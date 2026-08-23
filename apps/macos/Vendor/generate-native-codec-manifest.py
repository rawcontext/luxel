#!/usr/bin/env python3

import argparse
import hashlib
import json
import pathlib
import subprocess


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

CODECS = [
    {
        "id": "libvpx",
        "name": "libvpx",
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
        "headers": "macos-arm64/Headers",
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
    {
        "id": "libopus",
        "name": "libopus",
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
        "headers": "macos-arm64/Headers",
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
    {
        "id": "svt-av1",
        "name": "SVT-AV1",
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
        "headers": "macos-arm64/Headers",
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
]


def run(*command: str) -> str:
    return subprocess.check_output(command, text=True).strip()


def file_sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def directory_metadata(root: pathlib.Path) -> dict[str, object]:
    digest = hashlib.sha256()
    byte_size = 0
    file_count = 0
    for child in sorted(path for path in root.rglob("*") if path.is_file()):
        relative_path = child.relative_to(root).as_posix()
        child_digest = bytes.fromhex(file_sha256(child))
        digest.update(relative_path.encode("utf-8"))
        digest.update(b"\0")
        digest.update(child_digest)
        byte_size += child.stat().st_size
        file_count += 1
    return {"sha256": digest.hexdigest(), "bytes": byte_size, "files": file_count}


def build_metadata() -> dict[str, object]:
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


def require_expected_toolchain(build: dict[str, object]) -> None:
    if build != EXPECTED_BUILD:
        differences = [
            f"{key}: expected {EXPECTED_BUILD[key]!r}, found {build.get(key)!r}"
            for key in EXPECTED_BUILD
            if build.get(key) != EXPECTED_BUILD[key]
        ]
        raise SystemExit("Native codec toolchain mismatch: " + "; ".join(differences))


def artifact_metadata(codec: dict[str, object]) -> dict[str, object]:
    xcframework = ARTIFACT_ROOT / str(codec["xcframework"])
    library = xcframework / str(codec["library"])
    headers = xcframework / str(codec["headers"])
    if not library.is_file() or not headers.is_dir():
        raise SystemExit(f"Native codec artifact is missing: {xcframework}")

    return {
        "id": codec["id"],
        "name": codec["name"],
        "version": codec["version"],
        "tag": codec["tag"],
        "runtimeVersion": codec["runtimeVersion"],
        "source": codec["source"],
        "xcframework": codec["xcframework"],
        "library": {
            "relativePath": codec["library"],
            "sha256": file_sha256(library),
            "bytes": library.stat().st_size,
        },
        "headers": {
            "relativePath": codec["headers"],
            **directory_metadata(headers),
        },
        "licenses": codec["licenses"],
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--verify-toolchain-only", action="store_true")
    arguments = parser.parse_args()

    build = build_metadata()
    require_expected_toolchain(build)
    if arguments.verify_toolchain_only:
        print("Native codec build toolchain is pinned and valid.")
        return

    manifest = {
        "schemaVersion": 1,
        "build": build,
        "artifacts": [artifact_metadata(codec) for codec in CODECS],
    }
    MANIFEST_PATH.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    print(f"Wrote {MANIFEST_PATH}")


if __name__ == "__main__":
    main()
