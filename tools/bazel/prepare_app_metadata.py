"""Use separate development identity while preserving App Store metadata."""

from pathlib import Path
import plistlib
import sys

source, destination, mode = sys.argv[1:]
with Path(source).open("rb") as stream:
    info = plistlib.load(stream)
if mode == "development":
    info["CFBundleIdentifier"] = "com.rawcontext.luxel.dev"
    info["CFBundleName"] = "Luxel Dev"
    info["CFBundleDisplayName"] = "Luxel Dev"
    info["CFBundleURLTypes"][0]["CFBundleURLName"] = "com.rawcontext.luxel.dev.url"
    info["CFBundleURLTypes"][0]["CFBundleURLSchemes"] = ["luxel-dev"]
with Path(destination).open("wb") as stream:
    plistlib.dump(info, stream)
