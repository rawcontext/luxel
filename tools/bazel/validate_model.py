"""Materialize Bazel's symlinked inputs before applying the strict bundle audit."""

from pathlib import Path
import runpy
import shutil
import sys
import tempfile

script, model, source = sys.argv[1:]
auditor = runpy.run_path(script, run_name="luxel_model_auditor")
with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary) / model
    shutil.copytree(source, root)
    auditor["audit_directory"](root, auditor["CONFIGURATIONS"][model])
