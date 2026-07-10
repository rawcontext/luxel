# MODNet Core ML conversion

`convert.sh` reproduces Luxel's bundled FP16 Core ML model from the official
video-adapted MODNet webcam checkpoint. It pins the upstream source revision,
checkpoint digest, Python version, and complete Python environment.
PyTorch 2.7.0 is intentionally used because it is the newest version tested by
Core ML Tools 9.0; newer PyTorch releases are not yet supported by that
converter release.

Run on Apple silicon macOS 26:

```sh
./apps/macos/Vendor/Models/modnet-tools/convert.sh
```

The conversion validates the fixed image contract against deterministic,
synthetic fixtures, writes visual difference sheets, compiles the model, and
requires at least 15 completed predictions per second before replacing the
vendored artifact. The manifest records measured accuracy, latency, size, and
the compiled directory checksum.
