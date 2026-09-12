"""Write a portable checksum beside a release archive."""

import hashlib
from pathlib import Path
import sys

source, destination = map(Path, sys.argv[1:])
with source.open("rb") as stream:
    digest = hashlib.file_digest(stream, "sha256").hexdigest()
destination.write_text(f"{digest}  {source.name}\n")
