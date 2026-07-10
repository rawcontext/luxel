#!/usr/bin/env python3

import argparse
import hashlib
import json
import pathlib
import shutil
import subprocess
import sys
import tempfile
import time

import coremltools as ct
import numpy as np
from PIL import Image
import torch


MODEL_NAME = "MODNetPortraitMatting"
INPUT_NAME = "cameraImage"
OUTPUT_NAME = "alphaMatte"
IMAGE_SIZE = 512
CHECKPOINT_SHA256 = "913b82b66558db39b6286c150f809017d7528c872b156eb14333c9c6cb52108b"
UPSTREAM_COMMIT = "28165a451e4610c9d77cfdf925a94610bb2810fb"


def sha256_file(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sha256_directory(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    for child in sorted(candidate for candidate in path.rglob("*") if candidate.is_file()):
        digest.update(child.relative_to(path).as_posix().encode("utf-8"))
        digest.update(b"\0")
        digest.update(bytes.fromhex(sha256_file(child)))
    return digest.hexdigest()


def make_fixture(kind: str) -> np.ndarray:
    y, x = np.mgrid[0:IMAGE_SIZE, 0:IMAGE_SIZE]
    if kind == "gradient":
        red = x / (IMAGE_SIZE - 1)
        green = y / (IMAGE_SIZE - 1)
        blue = 0.5 + 0.25 * np.sin(x / 19.0) * np.cos(y / 23.0)
        image = np.stack([red, green, blue], axis=-1)
    elif kind == "silhouette":
        background = ((x // 32 + y // 32) % 2) * 0.12 + 0.22
        image = np.stack([background * 0.8, background, background * 1.2], axis=-1)
        head = ((x - 256) ** 2) / (82**2) + ((y - 168) ** 2) / (105**2) <= 1
        shoulders = ((x - 256) ** 2) / (190**2) + ((y - 420) ** 2) / (180**2) <= 1
        subject = head | shoulders
        image[subject] = np.array([0.72, 0.42, 0.28])
    else:
        raise ValueError(f"unknown fixture: {kind}")
    return np.uint8(np.clip(image * 255.0, 0, 255))


class MatteOnlyMODNet(torch.nn.Module):
    def __init__(self, model: torch.nn.Module):
        super().__init__()
        self.model = model

    def forward(self, image: torch.Tensor) -> torch.Tensor:
        _, _, matte = self.model(image, True)
        return torch.clamp(matte, 0.0, 1.0)


def load_torch_model(upstream: pathlib.Path, checkpoint: pathlib.Path) -> torch.nn.Module:
    sys.path.insert(0, str(upstream))
    from src.models.modnet import MODNet

    model = MODNet(backbone_pretrained=False)
    state = torch.load(checkpoint, map_location="cpu", weights_only=True)
    state = {key.removeprefix("module."): value for key, value in state.items()}
    model.load_state_dict(state)
    model.eval()
    return MatteOnlyMODNet(model).eval()


def normalized_tensor(image: np.ndarray) -> torch.Tensor:
    tensor = torch.from_numpy(image.astype(np.float32)).permute(2, 0, 1).unsqueeze(0)
    return tensor / 127.5 - 1.0


def coreml_matte(value: object) -> np.ndarray:
    array = np.asarray(value, dtype=np.float32).squeeze()
    if array.shape != (IMAGE_SIZE, IMAGE_SIZE):
        raise RuntimeError(f"unexpected Core ML output shape {array.shape}")
    if array.max() > 1.0:
        array /= 65535.0
    return array


def convert_model(torch_model: torch.nn.Module, package_path: pathlib.Path) -> ct.models.MLModel:
    example = torch.zeros(1, 3, IMAGE_SIZE, IMAGE_SIZE)
    traced = torch.jit.trace(torch_model, example, strict=True)
    model = ct.convert(
        traced,
        convert_to="mlprogram",
        inputs=[
            ct.ImageType(
                name=INPUT_NAME,
                shape=example.shape,
                color_layout=ct.colorlayout.RGB,
                scale=1.0 / 127.5,
                bias=[-1.0, -1.0, -1.0],
            )
        ],
        outputs=[
            ct.ImageType(
                name=OUTPUT_NAME,
                color_layout=ct.colorlayout.GRAYSCALE_FLOAT16,
            )
        ],
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.macOS26,
    )
    model.author = "ZHKKKe/MODNet; Core ML conversion by Luxel"
    model.license = "Apache-2.0"
    model.short_description = "Video-adapted MODNet portrait alpha matting"
    model.input_description[INPUT_NAME] = "512 x 512 center-cropped RGB camera frame"
    model.output_description[OUTPUT_NAME] = "512 x 512 continuous foreground alpha matte"
    model.save(package_path)
    return model


def validate_model(
    torch_model: torch.nn.Module,
    coreml_model: ct.models.MLModel,
    fixtures_path: pathlib.Path,
) -> dict[str, dict[str, float]]:
    fixtures_path.mkdir(parents=True, exist_ok=True)
    metrics = {}
    for kind in ("gradient", "silhouette"):
        image = make_fixture(kind)
        with torch.no_grad():
            reference = torch_model(normalized_tensor(image)).numpy().squeeze()
        prediction = coreml_matte(coreml_model.predict({INPUT_NAME: Image.fromarray(image)})[OUTPUT_NAME])
        if prediction.shape != reference.shape:
            raise RuntimeError(
                f"fixture {kind} output shape {prediction.shape} does not match {reference.shape}"
            )
        if not np.isfinite(prediction).all() or prediction.min() < 0 or prediction.max() > 1:
            raise RuntimeError(f"fixture {kind} produced invalid alpha values")
        absolute_error = np.abs(prediction - reference)
        fixture_metrics = {
            "maximumAbsoluteError": float(absolute_error.max()),
            "p99AbsoluteError": float(np.percentile(absolute_error, 99)),
            "meanAbsoluteError": float(absolute_error.mean()),
        }
        if fixture_metrics["maximumAbsoluteError"] > 0.1:
            raise RuntimeError(f"fixture {kind} exceeded maximum error tolerance: {fixture_metrics}")
        if fixture_metrics["p99AbsoluteError"] > 0.01:
            raise RuntimeError(f"fixture {kind} exceeded p99 error tolerance: {fixture_metrics}")
        if fixture_metrics["meanAbsoluteError"] > 0.002:
            raise RuntimeError(f"fixture {kind} exceeded mean error tolerance: {fixture_metrics}")
        Image.fromarray(image).save(fixtures_path / f"{kind}-input.png")
        Image.fromarray(np.uint16(np.clip(reference, 0, 1) * 65535)).save(
            fixtures_path / f"{kind}-reference.png"
        )
        Image.fromarray(np.uint16(np.clip(prediction, 0, 1) * 65535)).save(
            fixtures_path / f"{kind}-coreml.png"
        )
        difference = np.uint8(np.clip(absolute_error / 0.1, 0, 1) * 255)
        Image.fromarray(difference, mode="L").save(fixtures_path / f"{kind}-difference.png")
        metrics[kind] = fixture_metrics
    return metrics


def benchmark(model: object) -> dict[str, float]:
    image = Image.fromarray(make_fixture("silhouette"))
    for _ in range(3):
        model.predict({INPUT_NAME: image})
    durations = []
    for _ in range(20):
        start = time.perf_counter()
        model.predict({INPUT_NAME: image})
        durations.append((time.perf_counter() - start) * 1000)
    return {
        "sampleCount": len(durations),
        "meanMilliseconds": float(np.mean(durations)),
        "p95Milliseconds": float(np.percentile(durations, 95)),
        "completedMattesPerSecond": float(1000.0 / np.mean(durations)),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--upstream", type=pathlib.Path, required=True)
    parser.add_argument("--checkpoint", type=pathlib.Path, required=True)
    parser.add_argument("--output", type=pathlib.Path, required=True)
    parser.add_argument("--fixtures", type=pathlib.Path, required=True)
    args = parser.parse_args()

    upstream_commit = subprocess.check_output(
        ["git", "-C", args.upstream, "rev-parse", "HEAD"], text=True
    ).strip()
    if upstream_commit != UPSTREAM_COMMIT:
        raise RuntimeError(f"unexpected upstream commit {upstream_commit}")
    checkpoint_sha = sha256_file(args.checkpoint)
    if checkpoint_sha != CHECKPOINT_SHA256:
        raise RuntimeError(f"unexpected checkpoint SHA-256 {checkpoint_sha}")

    args.output.mkdir(parents=True, exist_ok=True)
    package_path = args.output / f"{MODEL_NAME}.mlpackage"
    compiled_path = args.output / f"{MODEL_NAME}.mlmodelc"
    shutil.rmtree(package_path, ignore_errors=True)
    shutil.rmtree(compiled_path, ignore_errors=True)

    torch_model = load_torch_model(args.upstream, args.checkpoint)
    coreml_model = convert_model(torch_model, package_path)
    metrics = validate_model(torch_model, coreml_model, args.fixtures)

    with tempfile.TemporaryDirectory() as temporary_directory:
        subprocess.run(
            ["xcrun", "coremlcompiler", "compile", str(package_path), temporary_directory],
            check=True,
        )
        shutil.copytree(pathlib.Path(temporary_directory) / compiled_path.name, compiled_path)

    compiled_model = ct.models.CompiledMLModel(
        str(compiled_path), compute_units=ct.ComputeUnit.ALL
    )
    benchmark_metrics = benchmark(compiled_model)
    if benchmark_metrics["completedMattesPerSecond"] < 15:
        raise RuntimeError(f"compiled model missed the performance floor: {benchmark_metrics}")

    manifest = {
        "schemaVersion": 1,
        "upstream": {
            "repository": "https://github.com/ZHKKKe/MODNet",
            "commit": UPSTREAM_COMMIT,
        },
        "checkpoint": {
            "name": "modnet_webcam_portrait_matting.ckpt",
            "source": "https://drive.google.com/file/d/1Nf1ZxeJZJL8Qx9KadcYYyEmmlKhTADxX/view",
            "sha256": CHECKPOINT_SHA256,
            "license": "Apache-2.0",
        },
        "conversion": {
            "python": ".".join(map(str, sys.version_info[:3])),
            "pytorch": torch.__version__,
            "coremltools": ct.__version__,
            "numpy": np.__version__,
            "scriptSha256": sha256_file(pathlib.Path(__file__)),
            "requirementsLockSha256": sha256_file(pathlib.Path(__file__).with_name("requirements.lock")),
            "representation": "ML Program",
            "precision": "Float16",
            "minimumDeploymentTarget": "macOS 26",
            "computeUnits": "all",
        },
        "contract": {
            "input": {
                "name": INPUT_NAME,
                "type": "image<RGB, UInt8>",
                "shape": [1, 3, IMAGE_SIZE, IMAGE_SIZE],
                "scale": 1.0 / 127.5,
                "bias": [-1.0, -1.0, -1.0],
            },
            "output": {
                "name": OUTPUT_NAME,
                "type": "image<Grayscale, Float16>",
                "shape": [1, 1, IMAGE_SIZE, IMAGE_SIZE],
                "range": [0.0, 1.0],
            },
        },
        "validation": {
            "maximumAbsoluteErrorTolerance": 0.1,
            "p99AbsoluteErrorTolerance": 0.01,
            "meanAbsoluteErrorTolerance": 0.002,
            "fixtures": metrics,
            "benchmark": benchmark_metrics,
        },
        "artifact": {
            "directory": compiled_path.name,
            "sha256": sha256_directory(compiled_path),
            "byteSize": sum(path.stat().st_size for path in compiled_path.rglob("*") if path.is_file()),
        },
    }
    (args.output / "model-manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    shutil.rmtree(package_path)
    print(json.dumps(manifest, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
