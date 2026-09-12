"""Run the pinned SwiftLint against its declared source files."""

import json
import os
from pathlib import Path
import subprocess
import sys
from python.runfiles import runfiles

files = runfiles.Create()
manifest, config, executable = [files.Rlocation(path) for path in sys.argv[1:]]
source_list = Path(os.environ["TEST_TMPDIR"]) / "swiftlint-inputs.xcfilelist"
source_list.write_text("\n".join(files.Rlocation(path) for path in json.loads(Path(manifest).read_text())) + "\n")
environment = dict(os.environ, SCRIPT_INPUT_FILE_LIST_COUNT="1", SCRIPT_INPUT_FILE_LIST_0=str(source_list))
result = subprocess.run(
    [executable, "lint", "--strict", "--quiet", "--config", config, "--use-script-input-file-lists"],
    env=environment,
)
raise SystemExit(result.returncode)
