"""Prepare the same localized strings and fixtures for standalone Swift tests."""

from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

output, catalog, compiler = map(Path, sys.argv[1:4])
core = output / "Luxel_LuxelCore.bundle"
fixtures = output / "Luxel_LuxelCoreTests.bundle"
for bundle in [core, fixtures]:
    bundle.mkdir(parents=True)
    with (bundle / "Info.plist").open("wb") as stream:
        plistlib.dump({"CFBundleDevelopmentRegion": "en"}, stream)

subprocess.run([sys.executable, str(compiler), str(catalog), str(core)], check=True)
for source in map(Path, sys.argv[4:]):
    shutil.copyfile(source, fixtures / source.name)
