#!/usr/bin/env python3
"""Collect the selected licenses from the locked macOS Cargo dependency graph."""

import argparse
import json
from pathlib import Path
import subprocess
import tomllib


parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--check", action="store_true")
parser.add_argument("--bazel-manifest", type=Path)
parser.add_argument("--output", type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
packages = {}
if args.bazel_manifest:
    for manifest_path in json.loads(args.bazel_manifest.read_text()):
        manifest = Path(manifest_path)
        package = tomllib.loads(manifest.read_text())["package"]
        packages[(package["name"], package["version"])] = {
            **package, "manifest_path": str(manifest),
        }
else:
    for target in ["aarch64-apple-darwin", "x86_64-apple-darwin"]:
        metadata = json.loads(subprocess.check_output([
            "cargo", "metadata", "--format-version", "1", "--locked",
            "--filter-platform", target,
        ], cwd=root))
        resolved = {node["id"] for node in metadata["resolve"]["nodes"]}
        for package in metadata["packages"]:
            if package["id"] in resolved and package["source"] is not None:
                packages[package["id"]] = package

sections = [
    "# Luxel CLI third-party licenses\n\n"
    "These are the dependencies resolved for the universal macOS CLI, including "
    "build-time crates. Luxel CLI's original code is MIT licensed; these "
    "components retain the notices below. Where a crate offers a choice, the "
    "MIT license is selected. Unicode data retains the Unicode license.\n\n"
    "Generated from Cargo.lock by `python3 scripts/generate-license-notices.py`."
]
for package in sorted(packages.values(), key=lambda item: (item["name"], item["version"])):
    source = Path(package["manifest_path"]).parent
    license_id = package["license"]
    if license_id in {"MIT", "MIT OR Apache-2.0", "Apache-2.0 OR MIT", "Unlicense OR MIT"}:
        files = ["LICENSE-MIT"] if (source / "LICENSE-MIT").exists() else ["LICENSE"]
        selected = "MIT"
    elif license_id == "Unicode-3.0":
        files = ["LICENSE"]
        selected = "Unicode-3.0"
    elif license_id == "(MIT OR Apache-2.0) AND Unicode-3.0":
        files = ["LICENSE-MIT", "LICENSE-UNICODE"]
        selected = "MIT AND Unicode-3.0"
    else:
        raise SystemExit(f"Review the license for {package['name']}: {license_id}")
    files += [name for name in ["COPYRIGHT", "NOTICE"] if (source / name).is_file()]
    notices = []
    for name in files:
        text = (source / name).read_text().strip()
        if not text:
            raise SystemExit(f"Empty license notice: {source / name}")
        notices.append(f"### {name}\n\n```text\n{text}\n```")
    sections.append(
        f"## {package['name']} {package['version']}\n\n"
        f"Source: https://crates.io/crates/{package['name']}/{package['version']}\n\n"
        f"License: {selected}\n\n" + "\n\n".join(notices)
    )

output = "\n\n".join(sections) + "\n"
destination = args.output or root / "THIRD_PARTY_LICENSES.md"
if args.check:
    if not destination.exists() or destination.read_text() != output:
        raise SystemExit("Regenerate CLI notices with python3 scripts/generate-license-notices.py")
else:
    destination.write_text(output)
print(f"Verified notices for {len(packages)} CLI dependencies.")
