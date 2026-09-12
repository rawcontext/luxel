"""Execute a declared Python script with Bazel's pinned interpreter."""

from pathlib import Path
import runpy
import sys

sys.argv = sys.argv[1:]
sys.path.insert(0, str(Path(sys.argv[0]).resolve().parent))
runpy.run_path(sys.argv[0], run_name="__main__")
