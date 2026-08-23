# DeepFilterNet3 Core ML model notice

Luxel redistributes the compiled `DeepFilterNet3.mlmodelc` model and
`auxiliary.npz` data from `aufklarer/DeepFilterNet3-CoreML` at revision
`937bad9811f1ffc1a06ea0d676461b080b2bdc93`.

The Core ML conversion is based on `Rikorose/DeepFilterNet3`. Luxel selects the
Apache License 2.0 option published for the dual-licensed model weights and the
Core ML conversion.

- Core ML model: https://huggingface.co/aufklarer/DeepFilterNet3-CoreML
- Base model: https://github.com/Rikorose/DeepFilterNet
- License: https://www.apache.org/licenses/LICENSE-2.0

The exact source revision, artifact checksums, byte counts, and model contracts
are recorded in `manifest.json`. Luxel performs inference on-device and does
not download these model files at runtime.
