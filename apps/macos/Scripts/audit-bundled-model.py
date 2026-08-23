import hashlib
import json
import pathlib
import subprocess
import sys
import tempfile


SPEAKER_CONTRACT = {
    "sampleRate": 16000,
    "maximumBatchSize": 32,
    "audioWindowSamples": 160000,
    "models": {
        "segmentation": {
            "directory": "Segmentation.mlmodelc",
            "input": {
                "name": "audio",
                "dataType": "Float32",
                "shape": ["batch", 1, 160000],
            },
            "output": {
                "name": "log_probs",
                "dataType": "Float32",
                "shape": ["batch", 589, 7],
            },
        },
        "filterbank": {
            "directory": "FBank.mlmodelc",
            "input": {
                "name": "audio",
                "dataType": "Float32",
                "shape": ["batch", 1, 160000],
            },
            "output": {
                "name": "fbank_features",
                "dataType": "Float32",
                "shape": ["batch", 1, 80, 998],
            },
        },
        "embedding": {
            "directory": "Embedding.mlmodelc",
            "inputs": [
                {
                    "name": "fbank_features",
                    "dataType": "Float32",
                    "shape": ["batch", 1, 80, 998],
                },
                {
                    "name": "weights",
                    "dataType": "Float32",
                    "shape": ["batch", 589],
                },
            ],
            "output": {
                "name": "embedding",
                "dataType": "Float32",
                "shape": ["batch", 256],
            },
        },
        "pldaRho": {
            "directory": "PldaRho.mlmodelc",
            "input": {
                "name": "embeddings",
                "dataType": "Float32",
                "shape": ["batch", 256],
            },
            "output": {
                "name": "rho",
                "dataType": "Float32",
                "shape": ["batch", 128],
            },
        },
    },
    "supportFiles": [
        "config.json",
        "plda-parameters.json",
        "xvector-transform.json",
    ],
}

STUDIO_CONTRACT = {
    "fftSize": 960,
    "hopSize": 480,
    "erbBands": 32,
    "frequencyBins": 481,
    "deepFilterBins": 96,
    "deepFilterOrder": 5,
    "deepFilterLookahead": 2,
    "maximumFrameCount": 6000,
    "inputs": [
        {
            "name": "feat_erb",
            "dataType": "Float16",
            "shape": [1, 1, "frames", 32],
        },
        {
            "name": "feat_spec",
            "dataType": "Float16",
            "shape": [1, 2, "frames", 96],
        },
    ],
    "outputs": [
        {
            "name": "erb_mask",
            "dataType": "Float16",
            "shape": [1, 1, "frames", 32],
        },
        {
            "name": "df_coefs",
            "dataType": "Float16",
            "shape": [1, 5, "frames", 96, 2],
        },
    ],
}

MODNET_ARTIFACTS = {
    "analytics/coremldata.bin": {
        "byteCount": 243,
        "sha256": "a2fb20b1ada819e765fc62520eef7c088849319dc180adb3028b3c9ccd29f623",
    },
    "coremldata.bin": {
        "byteCount": 506,
        "sha256": "d17f83b45a32e565cf8718559836df632a9590f1b004e1f3ca54931dfca78f2e",
    },
    "metadata.json": {
        "byteCount": 2211,
        "sha256": "023badc277f7212dc21e0dd6e9051abfe84f3a95f1fc11abc384628e2f66776f",
    },
    "model.mil": {
        "byteCount": 181345,
        "sha256": "b31886bd8393d469ca37f513dddea4d5989d53743c99bd11945df7871cfd67fb",
    },
    "weights/weight.bin": {
        "byteCount": 12938272,
        "sha256": "542b70422586d032b2a975b3de930c64f168d9a8420592d7bc8f106b98469dd5",
    },
}

VAD_ARTIFACTS = {
    "analytics/coremldata.bin": {
        "byteCount": 243,
        "sha256": "8067594eb3126ab8318af507f0c00cabfed40d5fedb8a0ee5075dd02e903d909",
    },
    "coremldata.bin": {
        "byteCount": 625,
        "sha256": "7db35a4fd995222a7fb0129713473b15d1462572ab4a2e5e4d56bcaad9e40f41",
    },
    "metadata.json": {
        "byteCount": 3335,
        "sha256": "2740be542c611e1ba358e1849b4e265c65cdf0b17192767e1e5de86a31ac94d6",
    },
    "model.mil": {
        "byteCount": 176918,
        "sha256": "c6a9d1bf22d413265da0a07a1d14151c3ea2fad296b3aa5859275b33ef1c3270",
    },
    "weights/weight.bin": {
        "byteCount": 882304,
        "sha256": "53ecc8b5081146140ab654c89109cf001f2183abddd7a2411c5081feeffff063",
    },
}

CONFIGURATIONS = {
    "speaker-diarization": {
        "label": "speaker diarization",
        "manifest": "model-manifest.json",
        "manifestKeys": {
            "schemaVersion",
            "repository",
            "revision",
            "sourceURL",
            "license",
            "artifactByteCount",
            "artifactTreeSHA256",
            "contract",
            "files",
        },
        "identity": {
            "schemaVersion": 1,
            "repository": "FluidInference/speaker-diarization-coreml",
            "revision": "1ed7a662fdc7109e36d822db793ee6eebdaf8594",
            "sourceURL": "https://huggingface.co/FluidInference/speaker-diarization-coreml/tree/1ed7a662fdc7109e36d822db793ee6eebdaf8594",
            "license": "CC-BY-4.0",
            "artifactByteCount": 21776918,
            "artifactTreeSHA256": "c343ed0130553e6fd7a81146bbcdd888a6d2042df85299763fc604085a568543",
            "contract": SPEAKER_CONTRACT,
        },
        "artifactCount": 23,
        "legalHashes": {
            "LICENSE.txt": "860739025785fc25c17773d7c55171228998a1faf34853d0c6fa303d067a68e1",
            "NOTICE.md": "58e1698638cd617bc1b955fddf341f2ac5522e3f333de23405536cc320744458",
        },
    },
    "studio-voice": {
        "label": "Studio Voice",
        "manifest": "manifest.json",
        "manifestKeys": {
            "schemaVersion",
            "repository",
            "revision",
            "sourceURL",
            "license",
            "sampleRate",
            "runtime",
            "artifactByteCount",
            "artifactTreeSHA256",
            "contract",
            "files",
        },
        "identity": {
            "schemaVersion": 1,
            "repository": "aufklarer/DeepFilterNet3-CoreML",
            "revision": "937bad9811f1ffc1a06ea0d676461b080b2bdc93",
            "sourceURL": "https://huggingface.co/aufklarer/DeepFilterNet3-CoreML/tree/937bad9811f1ffc1a06ea0d676461b080b2bdc93",
            "license": "Apache-2.0",
            "sampleRate": 48000,
            "runtime": "Adapted from soniqo/speech-swift v0.0.26 (f9af2f34d196eacca85d13fe508d8ed71919671f)",
            "artifactByteCount": 2472038,
            "artifactTreeSHA256": "50385d8dc28e911837f0e71855b32471db0a0f602c7e653a23846d6e54c1f4e8",
            "contract": STUDIO_CONTRACT,
        },
        "artifactCount": 5,
        "legalHashes": {
            "LICENSE.txt": "93225f964dc2832b9556149aaeda3bb9eb828db2408d170eb21faeb1cc87cda5",
            "NOTICE.md": "f5bdad38ba46ce217bb3abfa786091e71024c133536c374025a39aed062eead8",
        },
    },
    "modnet": {
        "label": "MODNet",
        "manifest": "model-manifest.json",
        "manifestKeys": {
            "artifact",
            "checkpoint",
            "contract",
            "conversion",
            "schemaVersion",
            "upstream",
            "validation",
        },
        "identity": {
            "schemaVersion": 1,
            "upstream": {
                "repository": "https://github.com/ZHKKKe/MODNet",
                "commit": "28165a451e4610c9d77cfdf925a94610bb2810fb",
            },
            "checkpoint": {
                "name": "modnet_webcam_portrait_matting.ckpt",
                "source": "https://drive.google.com/file/d/1Nf1ZxeJZJL8Qx9KadcYYyEmmlKhTADxX/view",
                "sha256": "913b82b66558db39b6286c150f809017d7528c872b156eb14333c9c6cb52108b",
                "license": "Apache-2.0",
            },
            "conversion": {
                "python": "3.13.15",
                "pytorch": "2.7.0",
                "coremltools": "9.0",
                "numpy": "2.5.2",
                "uv": "0.12.5",
                "driverScriptSha256": "c198ae6573fa10189baa2d4694f55633c3a9328b8bdb5a3b61681da413367143",
                "requirementsInputSha256": "f05f71a8b4fa9e29d5c97497c7bc0d835eec012d3a616df4114ca4a81426fada",
                "requirementsLockSha256": "385f0471d1b925adb9d7ab10bb9be93d3109575dfed882c2835c4648fc95afeb",
                "scriptSha256": "d525e498fe77bdd6293d862edb6c5cc0f0cc5e9d29908f61f44e8ad6f3a6ff0a",
                "coremlcompilerSha256": "ea1cd3a446a1d38d2bae94501d274fc9cf395db865f8ad600573b381e408d85d",
                "xcode": "26.6",
                "xcodeBuild": "17F113",
                "representation": "ML Program",
                "precision": "Float16",
                "minimumDeploymentTarget": "macOS 26",
                "computeUnits": "all",
            },
            "contract": {
                "input": {
                    "bias": [-1.0, -1.0, -1.0],
                    "name": "cameraImage",
                    "scale": 0.00784313725490196,
                    "shape": [1, 3, 512, 512],
                    "type": "image<RGB, UInt8>",
                },
                "output": {
                    "name": "alphaMatte",
                    "range": [0.0, 1.0],
                    "shape": [1, 1, 512, 512],
                    "type": "image<Grayscale, Float16>",
                },
            },
            "validation": {
                "benchmark": {
                    "minimumCompletedMattesPerSecond": 15,
                    "sampleCount": 20,
                },
                "computeUnits": "all",
                "fixtures": ["gradient", "silhouette"],
                "maximumAbsoluteErrorTolerance": 0.1,
                "meanAbsoluteErrorTolerance": 0.002,
                "p99AbsoluteErrorTolerance": 0.01,
            },
            "artifact": {
                "byteSize": 13122577,
                "directory": "MODNetPortraitMatting.mlmodelc",
                "files": {
                    relative_path: entry["sha256"]
                    for relative_path, entry in MODNET_ARTIFACTS.items()
                },
                "sha256": "d0fc8c34ea739ad6fbb144ebce3f334f5994b6ba87332a6be168970da51b6650",
            },
        },
        "artifactRoot": "MODNetPortraitMatting.mlmodelc",
        "expectedArtifacts": MODNET_ARTIFACTS,
        "artifactCount": 5,
        "artifactByteCount": 13122577,
        "artifactTreeSHA256": "d0fc8c34ea739ad6fbb144ebce3f334f5994b6ba87332a6be168970da51b6650",
        "legalHashes": {
            "LICENSE.txt": "c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4",
            "NOTICE.md": "c04008686fe0c4cee234c3ad7b4ac6eb22c385745050c5ca6404e85443a65176",
        },
    },
    "voice-activity-detection": {
        "label": "voice activity detection",
        "manifest": "model-manifest.json",
        "manifestKeys": {
            "artifact",
            "contract",
            "license",
            "modelVersion",
            "schemaVersion",
            "upstream",
        },
        "identity": {
            "schemaVersion": 1,
            "modelVersion": "6.2.1",
            "license": "MIT",
            "upstream": {
                "repository": "https://huggingface.co/FluidInference/silero-vad-coreml",
                "revision": "b419383c55c110e2c9271fa6ee0ea83d03c70d96",
                "sileroRepository": "https://github.com/snakers4/silero-vad",
            },
            "contract": {
                "audioInputSamples": 4096,
                "contextSamples": 64,
                "inputDataType": "Float32",
                "inputShape": [1, 4160],
                "inputs": {
                    "audio": {
                        "dataType": "Float32",
                        "name": "audio_input",
                        "shape": [1, 4160],
                    },
                    "cellState": {
                        "dataType": "Float32",
                        "name": "cell_state",
                        "shape": [1, 128],
                    },
                    "hiddenState": {
                        "dataType": "Float32",
                        "name": "hidden_state",
                        "shape": [1, 128],
                    },
                },
                "outputs": {
                    "cellState": {
                        "dataType": "Float32",
                        "name": "new_cell_state",
                        "shape": [1, 128],
                    },
                    "hiddenState": {
                        "dataType": "Float32",
                        "name": "new_hidden_state",
                        "shape": [1, 128],
                    },
                    "probability": {
                        "dataType": "Float32",
                        "name": "vad_output",
                        "shape": [1, 1, 1],
                    },
                },
                "sampleRate": 16000,
                "stateSize": 128,
            },
            "artifact": {
                "byteSize": 1063425,
                "directory": "silero-vad-unified-256ms-v6.2.1.mlmodelc",
                "files": {
                    relative_path: entry["sha256"]
                    for relative_path, entry in VAD_ARTIFACTS.items()
                },
                "sha256": "b96c5a462e5b8d475caffcd2a70928ae546c0eb9acc44bf98b1e1b9b22128497",
            },
        },
        "artifactRoot": "silero-vad-unified-256ms-v6.2.1.mlmodelc",
        "expectedArtifacts": VAD_ARTIFACTS,
        "artifactCount": 5,
        "artifactByteCount": 1063425,
        "artifactTreeSHA256": "b96c5a462e5b8d475caffcd2a70928ae546c0eb9acc44bf98b1e1b9b22128497",
        "legalHashes": {
            "LICENSE.txt": "51c19c8be941a3fb00ccf58f0bf9053de9f7237a0b37327896eabad32dffe873",
            "NOTICE.md": "5b72531707a50e1ea44163aed22b16939ce490ae7007c28f7db22eaab54c5238",
        },
    },
}


class AuditError(Exception):
    pass


def resolve_model_directory(input_path, model_name, temporary_directory):
    if input_path.suffix == ".pkg":
        if not input_path.is_file():
            raise AuditError(f"Package does not exist: {input_path}")
        expanded = pathlib.Path(temporary_directory) / "expanded"
        result = subprocess.run(
            ["pkgutil", "--expand-full", str(input_path), str(expanded)],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            detail = result.stderr.strip() or result.stdout.strip()
            raise AuditError(f"Could not expand {input_path}: {detail}")
        app_paths = sorted(
            path
            for path in expanded.rglob("Luxel.app")
            if path.is_dir() and not path.is_symlink()
        )
        if len(app_paths) != 1:
            raise AuditError(
                f"Expected one Luxel.app in {input_path}, found {len(app_paths)}."
            )
        return app_paths[0] / "Contents/Resources/Models" / model_name

    if input_path.suffix == ".app":
        if not input_path.is_dir() or input_path.is_symlink():
            raise AuditError(f"App bundle does not exist or is a symlink: {input_path}")
        return input_path / "Contents/Resources/Models" / model_name

    return input_path


def load_manifest(root, configuration):
    manifest_path = root / configuration["manifest"]
    if not manifest_path.is_file():
        raise AuditError(f"Required manifest is missing: {manifest_path}")
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as error:
        raise AuditError(f"Could not read {manifest_path}: {error}") from error
    if not isinstance(manifest, dict):
        raise AuditError(f"Manifest must contain a JSON object: {manifest_path}")
    if set(manifest) != configuration["manifestKeys"]:
        raise AuditError(f"Manifest field set is missing or unexpected: {manifest_path}")
    for field, expected in configuration["identity"].items():
        if manifest.get(field) != expected:
            raise AuditError(
                f"{configuration['label']} manifest field is missing or unexpected: {field}"
            )
    return manifest


def artifact_entries(manifest, configuration):
    expected_entries = configuration.get("expectedArtifacts")
    if expected_entries is not None:
        if len(expected_entries) != configuration["artifactCount"]:
            raise AuditError(
                f"Internal {configuration['label']} artifact configuration is malformed."
            )
        return expected_entries

    entries = manifest.get("files")
    if not isinstance(entries, list) or len(entries) != configuration["artifactCount"]:
        raise AuditError(
            f"{configuration['label']} manifest must contain exactly "
            f"{configuration['artifactCount']} artifact entries."
        )

    by_path = {}
    for entry in entries:
        if not isinstance(entry, dict) or set(entry) != {"path", "byteCount", "sha256"}:
            raise AuditError(f"Malformed {configuration['label']} artifact entry.")
        relative_path = entry.get("path")
        if (
            not isinstance(relative_path, str)
            or not relative_path
            or pathlib.PurePosixPath(relative_path).is_absolute()
            or ".." in pathlib.PurePosixPath(relative_path).parts
            or relative_path in by_path
        ):
            raise AuditError(f"Invalid {configuration['label']} artifact path.")
        if not isinstance(entry.get("byteCount"), int) or entry["byteCount"] < 0:
            raise AuditError(f"Invalid byte count for {relative_path}.")
        digest = entry.get("sha256")
        if (
            not isinstance(digest, str)
            or len(digest) != 64
            or any(character not in "0123456789abcdef" for character in digest)
        ):
            raise AuditError(f"Invalid SHA-256 for {relative_path}.")
        by_path[relative_path] = entry

    if list(by_path) != sorted(by_path):
        raise AuditError(f"{configuration['label']} artifact entries are not sorted.")
    return by_path


def audit_directory(root, configuration):
    if not root.is_dir() or root.is_symlink():
        raise AuditError(f"Required {configuration['label']} directory is missing: {root}")

    manifest = load_manifest(root, configuration)
    entries = artifact_entries(manifest, configuration)
    legal_hashes = configuration["legalHashes"]
    artifact_root = configuration.get("artifactRoot")
    artifact_prefix = f"{artifact_root}/" if artifact_root else ""
    expected_files = (
        {f"{artifact_prefix}{relative_path}" for relative_path in entries}
        | set(legal_hashes)
        | {configuration["manifest"]}
    )

    actual_files = set()
    for path in root.rglob("*"):
        if path.is_symlink():
            raise AuditError(f"Symlinks are not allowed in bundled model resources: {path}")
        if path.is_file():
            actual_files.add(path.relative_to(root).as_posix())
    if actual_files != expected_files:
        missing = sorted(expected_files - actual_files)
        unexpected = sorted(actual_files - expected_files)
        raise AuditError(
            f"{configuration['label']} file set does not match the manifest; "
            f"missing={missing}, unexpected={unexpected}."
        )

    for relative_path, expected_digest in legal_hashes.items():
        digest = hashlib.sha256((root / relative_path).read_bytes()).hexdigest()
        if digest != expected_digest:
            raise AuditError(
                f"{configuration['label']} legal resource checksum mismatch: {relative_path}"
            )

    tree_digest = hashlib.sha256()
    total_byte_count = 0
    for relative_path, entry in entries.items():
        path = root / artifact_root / relative_path if artifact_root else root / relative_path
        data = path.read_bytes()
        digest = hashlib.sha256(data)
        if len(data) != entry["byteCount"]:
            raise AuditError(
                f"{configuration['label']} artifact byte count mismatch: {relative_path}"
            )
        if digest.hexdigest() != entry["sha256"]:
            raise AuditError(
                f"{configuration['label']} artifact checksum mismatch: {relative_path}"
            )
        tree_digest.update(relative_path.encode("utf-8"))
        tree_digest.update(b"\0")
        tree_digest.update(digest.digest())
        total_byte_count += len(data)

    expected_byte_count = configuration.get(
        "artifactByteCount", configuration["identity"].get("artifactByteCount")
    )
    expected_tree_digest = configuration.get(
        "artifactTreeSHA256", configuration["identity"].get("artifactTreeSHA256")
    )
    if total_byte_count != expected_byte_count:
        raise AuditError(f"{configuration['label']} artifact size does not match manifest.")
    if tree_digest.hexdigest() != expected_tree_digest:
        raise AuditError(
            f"{configuration['label']} artifact tree checksum does not match manifest."
        )

    print(
        f"Verified {configuration['label']} model: "
        f"{len(entries)} artifacts, {total_byte_count} bytes, "
        f"SHA-256 {tree_digest.hexdigest()}"
    )


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in CONFIGURATIONS:
        choices = "|".join(CONFIGURATIONS)
        raise AuditError(
            f"Usage: {pathlib.Path(sys.argv[0]).name} "
            f"<{choices}> <model-directory|app-bundle|package>"
        )

    model_name = sys.argv[1]
    configuration = CONFIGURATIONS[model_name]
    with tempfile.TemporaryDirectory(prefix=f"luxel-{model_name}-audit-") as temporary:
        root = resolve_model_directory(pathlib.Path(sys.argv[2]), model_name, temporary)
        audit_directory(root, configuration)


if __name__ == "__main__":
    try:
        main()
    except AuditError as error:
        print(error, file=sys.stderr)
        raise SystemExit(1) from None
