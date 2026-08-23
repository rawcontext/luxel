# MODNet Core ML conversion

`convert.sh` reproduces Luxel's bundled FP16 Core ML model from the official
video-adapted MODNet webcam checkpoint. It pins the upstream source revision,
checkpoint digest, Python version, and complete Python environment.
PyTorch 2.7.0 is intentionally used because it is the newest version tested by
Core ML Tools 9.0; newer PyTorch releases are not yet supported by that
converter release.

Regenerate the hashed conversion lock from its direct inputs with the repository-pinned
`uv` release:

```sh
uv pip compile apps/macos/Vendor/Models/modnet-tools/requirements.in \
  --python 3.13.15 \
  --python-platform aarch64-apple-darwin \
  --upgrade \
  --generate-hashes \
  --no-header \
  --output-file apps/macos/Vendor/Models/modnet-tools/requirements.lock
```

Run on Apple silicon macOS 26 with Xcode 26.6 build 17F113 selected:

```sh
./apps/macos/Vendor/Models/modnet-tools/convert.sh
```

Each invocation creates a fresh isolated checkout of the pinned upstream commit
and a fresh virtual environment. Cached upstream source and Python environments
are never executed. The checkpoint download remains cached only after its digest
is verified.

The conversion verifies the exact Xcode and `coremlcompiler` binary, validates the
fixed image contract against deterministic synthetic fixtures with the production
compute-unit policy, compiles the model, and requires at least 15 completed predictions per
second. Measured accuracy and benchmark timing are printed as run evidence but
are not written to the manifest or fixture files. The manifest records the fixed
validation contract, toolchain identity, model size, and compiled directory
checksum, plus every compiled file checksum.

`coremlcompiler` may reorder equivalent metadata in `coremldata.bin`. The update
step compares every compiled runtime file. A byte-different bundle is retained
only when its model graph, weights, and normalized metadata match, its recorded
Xcode/compiler identity matches the current pinned toolchain, and production-path
fixture validation plus the performance floor pass against that exact retained
bundle. Corrupt compiler output is replaced instead of being re-hashed. Fixed
manifest values and non-persisted measurements keep a second identical run from
changing tracked files.
