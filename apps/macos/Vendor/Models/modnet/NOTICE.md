# MODNet notice

Luxel redistributes the video-adapted `modnet_webcam_portrait_matting.ckpt`
from [ZHKKKe/MODNet](https://github.com/ZHKKKe/MODNet), converted to an FP16
Core ML ML Program for local portrait matting.

MODNet is Copyright 2020 Zhanghan Ke and contributors and is licensed under
the Apache License 2.0. The checkpoint source and exact provenance are recorded
in `model-manifest.json`. Camera frames and mattes remain on-device; this model
does not require networking at runtime.
