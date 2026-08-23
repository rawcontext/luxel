# Speaker diarization model notice

Luxel redistributes an unmodified subset of the
`FluidInference/speaker-diarization-coreml` Core ML model repository at
revision `1ed7a662fdc7109e36d822db793ee6eebdaf8594`.

The models are based on `pyannote/speaker-diarization-community-1` and
WeSpeaker. They are licensed under Creative Commons Attribution 4.0
International (CC-BY-4.0).

- Core ML conversion: FluidInference
- Speaker segmentation: pyannote.audio contributors, including Hervé Bredin
- Speaker embedding: WeSpeaker contributors
- Model repository: https://huggingface.co/FluidInference/speaker-diarization-coreml
- License: https://creativecommons.org/licenses/by/4.0/legalcode.en

The exact source revision, artifact checksums, byte counts, and model contracts
are recorded in `model-manifest.json`. Luxel performs inference on-device and
does not download these model files at runtime.
