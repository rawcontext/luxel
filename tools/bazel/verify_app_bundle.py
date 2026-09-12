"""Validate the actual Bazel app payload before signing or publication."""

import json
import os
from pathlib import Path
import plistlib
import runpy
import stat
import sys
from zipfile import ZipFile
from python.runfiles import runfiles

files = runfiles.Create()
archive, source_info, privacy, notices, license_file, catalog, auditor = [
    Path(files.Rlocation(path)) for path in sys.argv[1:8]
]
identifier, display_name, scheme = sys.argv[8:11]
original = plistlib.loads(source_info.read_bytes())
locales = {
    locale
    for entry in json.loads(catalog.read_text())["strings"].values()
    for locale in entry.get("localizations", {})
}
root = "Luxel.app/Contents/"
resources = root + "Resources/"
with ZipFile(archive) as bundle:
    info = plistlib.loads(bundle.read(root + "Info.plist"))
    assert info["CFBundleIdentifier"] == identifier
    assert info["CFBundleDisplayName"] == display_name
    assert info["CFBundleExecutable"] == "Luxel"
    assert info["CFBundleShortVersionString"] == original["CFBundleShortVersionString"]
    assert info["LSUIElement"] is True
    assert info["CFBundleURLTypes"][0]["CFBundleURLSchemes"] == [scheme]
    assert info["CFBundleDocumentTypes"] == original["CFBundleDocumentTypes"]
    for key, value in original.items():
        if key.endswith("UsageDescription"):
            assert info[key] == value, key
    for name, source in [("PrivacyInfo.xcprivacy", privacy), ("ThirdPartyLicenses.md", notices), ("LICENSE.txt", license_file)]:
        assert bundle.read(resources + name) == source.read_bytes(), name
    for name in ["Assets.car", "Luxel.icns", "FluidAudio_FluidAudio.bundle/Info.plist"]:
        assert bundle.read(resources + name), name
    for locale in locales:
        assert bundle.read(resources + f"Luxel_LuxelCore.bundle/{locale}.lproj/Localizable.strings"), locale
        assert bundle.read(resources + f"{locale}.lproj/InfoPlist.strings"), locale
    for entry in bundle.infolist():
        assert not entry.filename.endswith((".p8", ".p12", ".pfx", ".keychain-db")), entry.filename
        if entry.filename.startswith(resources + "Models/"):
            assert not stat.S_ISLNK(entry.external_attr >> 16), entry.filename
    destination = Path(os.environ["TEST_TMPDIR"]) / "app"
    bundle.extractall(destination)

model_auditor = runpy.run_path(str(auditor), run_name="luxel_model_auditor")
for name, configuration in model_auditor["CONFIGURATIONS"].items():
    model_auditor["audit_directory"](destination / resources / "Models" / name, configuration)
print("Verified app identity, privacy, licenses, icons, all localizations, and all bundled models.")
