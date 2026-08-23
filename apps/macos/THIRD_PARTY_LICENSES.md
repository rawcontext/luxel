# Third-Party Licenses

Luxel ships the following third-party components:

1. libvpx — BSD-3-Clause — WebM (VP8/VP9) video export
2. libopus — BSD-3-Clause — WebM/Opus audio export
3. SVT-AV1 — BSD-3-Clause-Clear — AV1 video export
4. AOM-derived SVT-AV1 components — BSD-2-Clause — AV1 codec primitives embedded in SVT-AV1
5. dav1d-derived SVT-AV1 assembly — BSD-2-Clause — ARM assembly embedded in SVT-AV1
6. fastfeat — BSD-3-Clause — FAST corner detection embedded in SVT-AV1
7. FluidAudio — Apache License 2.0 — local speaker diarization engine
8. NemoTextProcessing — Apache-2.0 — statically linked text normalization supplied by FluidAudio
9. fastcluster — BSD-2-Clause — hierarchical clustering code included by FluidAudio
10. VBx — Apache License 2.0 — speaker clustering implementation included by FluidAudio
11. FluidInference speaker-diarization-coreml — CC-BY-4.0 — bundled speaker diarization Core ML models
12. FluidInference silero-vad-coreml — MIT — bundled local voice activity detection model
13. aufklarer/DeepFilterNet3-CoreML — Apache License 2.0 — bundled Studio Voice Core ML model
14. soniqo/speech-swift — Apache License 2.0 — adapted Studio Voice signal-processing runtime
15. ZHKKKe/MODNet — Apache License 2.0 — bundled local camera portrait-matting model

The license notices and required attributions for each component follow in the
same order. Shared license text is reproduced once and referenced by every
component to which it applies.

## Dependency: libvpx
Name: libvpx
License: BSD-3-Clause
Copyright: Copyright (c) 2010, The WebM Project authors. All rights reserved.
License Text:
Copyright (c) 2010, The WebM Project authors. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

  * Redistributions of source code must retain the above copyright
    notice, this list of conditions and the following disclaimer.

  * Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in
    the documentation and/or other materials provided with the
    distribution.

  * Neither the name of Google, nor the WebM Project, nor the names
    of its contributors may be used to endorse or promote products
    derived from this software without specific prior written
    permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

Patent grant: Google Additional IP Rights Grant from the vendored `PATENTS` file.

## Dependency: libopus
Name: libopus
License: BSD-3-Clause
Copyright: Copyright 2001-2023 Xiph.Org, Skype Limited, Octasic, Jean-Marc Valin, Timothy B. Terriberry, CSIRO, Gregory Maxwell, Mark Borgerding, Erik de Castro Lopo, Mozilla, Amazon
License Text:
Copyright 2001-2023 Xiph.Org, Skype Limited, Octasic,
                    Jean-Marc Valin, Timothy B. Terriberry,
                    CSIRO, Gregory Maxwell, Mark Borgerding,
                    Erik de Castro Lopo, Mozilla, Amazon

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

- Redistributions of source code must retain the above copyright
notice, this list of conditions and the following disclaimer.

- Redistributions in binary form must reproduce the above copyright
notice, this list of conditions and the following disclaimer in the
documentation and/or other materials provided with the distribution.

- Neither the name of Internet Society, IETF or IETF Trust, nor the
names of specific contributors, may be used to endorse or promote
products derived from this software without specific prior written
permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER
OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

Opus is subject to the royalty-free patent licenses specified by Xiph.Org Foundation, Microsoft Corporation, and Broadcom Corporation.

## Dependency: svt-av1
Name: SVT-AV1
License: BSD-3-Clause-Clear
Copyright: Copyright (c) 2021, Alliance for Open Media; Copyright(c) 2019 Intel Corporation
License Text:
BSD 3-Clause Clear License
The Clear BSD License

Copyright (c) 2021, Alliance for Open Media

All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted (subject to the limitations in the disclaimer below)
provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in
   the documentation and/or other materials provided with the distribution.

3. Neither the name of the Alliance for Open Media nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

NO EXPRESS OR IMPLIED LICENSES TO ANY PARTY'S PATENT RIGHTS ARE GRANTED BY THIS LICENSE.
THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT
OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

Alliance for Open Media Patent License 1.0

1. License Terms.

   Patent License. Subject to the terms and conditions of this License, each
   Licensor, on behalf of itself and successors in interest and assigns,
   grants Licensee a non-sublicensable, perpetual, worldwide, non-exclusive,
   no-charge, royalty-free, irrevocable (except as expressly stated in this
   License) patent license to its Necessary Claims to make, use, sell, offer
   for sale, import or distribute any Implementation.

   Conditions.

   Availability. As a condition to the grant of rights to Licensee to make,
   sell, offer for sale, import or distribute an Implementation under
   Section 1.1, Licensee must make its Necessary Claims available under
   this License, and must reproduce this License with any Implementation
   as follows:

      a. For distribution in source code, by including this License in the
      root directory of the source code with its Implementation.

      b. For distribution in any other form (including binary, object form,
      and/or hardware description code (e.g., HDL, RTL, Gate Level Netlist,
      GDSII, etc.)), by including this License in the documentation, legal
      notices, and/or other written materials provided with the
      Implementation.

   Additional Conditions. This license is directly from Licensor to
   Licensee. Licensee acknowledges as a condition of benefiting from it
   that no rights from Licensor are received from suppliers, distributors,
   or otherwise in connection with this License.

   Defensive Termination. If any Licensee, its Affiliates, or its agents
   initiates patent litigation or files, maintains, or voluntarily
   participates in a lawsuit against another entity or any person asserting
   that any Implementation infringes Necessary Claims, any patent licenses
   granted under this License directly to the Licensee are immediately
   terminated as of the date of the initiation of action unless 1) that suit
   was in response to a corresponding suit regarding an Implementation first
   brought against an initiating entity, or 2) that suit was brought to
   enforce the terms of this License (including intervention in a third-party
   action by a Licensee).

   Disclaimers. The Reference Implementation and Specification are provided
   "AS IS" and without warranty. The entire risk as to implementing or
   otherwise using the Reference Implementation or Specification is assumed
   by the implementer and user. Licensor expressly disclaims any warranties
   (express, implied, or otherwise), including implied warranties of
   merchantability, non-infringement, fitness for a particular purpose, or
   title, related to the material. IN NO EVENT WILL LICENSOR BE LIABLE TO
   ANY OTHER PARTY FOR LOST PROFITS OR ANY FORM OF INDIRECT, SPECIAL,
   INCIDENTAL, OR CONSEQUENTIAL DAMAGES OF ANY CHARACTER FROM ANY CAUSES OF
   ACTION OF ANY KIND WITH RESPECT TO THIS LICENSE, WHETHER BASED ON BREACH
   OF CONTRACT, TORT (INCLUDING NEGLIGENCE), OR OTHERWISE, AND WHETHER OR
   NOT THE OTHER PARTRY HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

2. Definitions.

   Affiliate. "Affiliate" means an entity that directly or indirectly
   Controls, is Controlled by, or is under common Control of that party.

   Control. "Control" means direct or indirect control of more than 50% of
   the voting power to elect directors of that corporation, or for any other
   entity, the power to direct management of such entity.

   Decoder. "Decoder" means any decoder that conforms fully with all
   non-optional portions of the Specification.

   Encoder. "Encoder" means any encoder that produces a bitstream that can
   be decoded by a Decoder only to the extent it produces such a bitstream.

   Final Deliverable. "Final Deliverable" means the final version of a
   deliverable approved by the Alliance for Open Media as a Final
   Deliverable.

   Implementation. "Implementation" means any implementation, including the
   Reference Implementation, that is an Encoder and/or a Decoder. An
   Implementation also includes components of an Implementation only to the
   extent they are used as part of an Implementation.

   License. "License" means this license.

   Licensee. "Licensee" means any person or entity who exercises patent
   rights granted under this License.

   Licensor. "Licensor" means (i) any Licensee that makes, sells, offers
   for sale, imports or distributes any Implementation, or (ii) a person
   or entity that has a licensing obligation to the Implementation as a
   result of its membership and/or participation in the Alliance for Open
   Media working group that developed the Specification.

   Necessary Claims. "Necessary Claims" means all claims of patents or
   patent applications, (a) that currently or at any time in the future,
   are owned or controlled by the Licensor, and (b) (i) would be an
   Essential Claim as defined by the W3C Policy as of February 5, 2004
   (https://www.w3.org/Consortium/Patent-Policy-20040205/#def-essential)
   as if the Specification was a W3C Recommendation; or (ii) are infringed
   by the Reference Implementation.

   Reference Implementation. "Reference Implementation" means an Encoder
   and/or Decoder released by the Alliance for Open Media as a Final
   Deliverable.

   Specification. "Specification" means the specification designated by
   the Alliance for Open Media as a Final Deliverable for which this
   License was issued.

## Dependency: svt-av1-aom
Name: AOM-derived SVT-AV1 components
License: BSD-2-Clause
Copyright: Copyright (c) 2019, Alliance for Open Media. All rights reserved.
License Text:
Copyright (c) 2019, Alliance for Open Media. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in
   the documentation and/or other materials provided with the
   distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.

The Alliance for Open Media Patent License 1.0 reproduced with the SVT-AV1 notice applies to these components.

## Dependency: svt-av1-dav1d
Name: dav1d-derived SVT-AV1 assembly
License: BSD-2-Clause
Copyright: Copyright © 2018 VideoLAN and dav1d authors; Copyright © 2015, 2018 Janne Grunau; Copyright © 2015 Martin Storsjo
License Text:
Copyright © 2018, VideoLAN and dav1d authors
Copyright © 2015, 2018 Janne Grunau
Copyright © 2015 Martin Storsjo
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
   this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.

## Dependency: svt-av1-fastfeat
Name: fastfeat
License: BSD-3-Clause
Copyright: Copyright (c) 2006, 2008 Edward Rosten. All rights reserved.
License Text:
Copyright (c) 2006, 2008 Edward Rosten
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

* Redistributions of source code must retain the above copyright notice,
  this list of conditions and the following disclaimer.

* Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.

* Neither the name of the University of Cambridge nor the names of its
  contributors may be used to endorse or promote products derived from this
  software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
POSSIBILITY OF SUCH DAMAGE.

## FluidAudio

Luxel includes FluidAudio v0.15.6 at commit
`4dbf4f9f9a5ff3a53ade848d7ba4e3df13db859b` for local speaker diarization
and bundled Silero VAD inference. Luxel enables FluidAudio's offline mode and
loads only audited local model directories; it does not use FluidAudio's model
download fallback.

License: Apache License 2.0 (full text reproduced in the "Apache License, Version 2.0" section below)

Copyright: Copyright 2025 Fluid Inference Inc.

Upstream license file: https://github.com/FluidInference/FluidAudio/blob/4dbf4f9f9a5ff3a53ade848d7ba4e3df13db859b/LICENSE

## NemoTextProcessing (included by FluidAudio)

FluidAudio v0.15.6 statically links `NemoTextProcessing` from
`FluidInference/text-processing-rs` v0.3.0 at commit
`27d75c401c225771fc16053dc551a887c2fbfc50`. SwiftPM verifies the
49,419,751-byte XCFramework release archive with checksum
`76d0ee9a32b1ee2193231299180ca9bc4fc7e98794e771b3d55d66498352d85f`.
It is a build-time binary dependency and performs no runtime download.

License: Apache License 2.0 (full text reproduced below)

The binary includes weighted-FST grammars derived from NVIDIA NeMo Text
Processing at commit `1f1263579fe57ba7ed783cad3dddee710fcc5064`
(Apache-2.0, Copyright NVIDIA CORPORATION & AFFILIATES) and permissively
licensed Rust dependencies including rustfst and flate2 (MIT OR Apache-2.0).

Upstream notice: https://github.com/FluidInference/FluidAudio/blob/4dbf4f9f9a5ff3a53ade848d7ba4e3df13db859b/ThirdPartyLicenses/NemoTextProcessing-LICENSE.md

Source: https://github.com/FluidInference/text-processing-rs/tree/v0.3.0

## fastcluster (included by FluidAudio)

FluidAudio includes a C++ wrapper and source from the fastcluster library for
hierarchical speaker clustering.

License: BSD 2-Clause License

Copyright: Until package version 1.1.23: Copyright 2011 Daniel Müllner; all changes from version 1.1.24 on: Copyright Google Inc. All rights reserved.

Upstream notice: https://github.com/FluidInference/FluidAudio/blob/4dbf4f9f9a5ff3a53ade848d7ba4e3df13db859b/ThirdPartyLicenses/fastcluster-LICENSE.md

Copyright:
  * Until package version 1.1.23: © 2011 Daniel Müllner <https://danifold.net>
  * All changes from version 1.1.24 on: © Google Inc. <https://www.google.com>
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

  * Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
  * Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

## VBx (included by FluidAudio)

FluidAudio includes an implementation based on the VBx speaker-diarization
algorithm from the Brno University of Technology Speech@FIT group.

License: Apache License 2.0 (full text reproduced in the "Apache License, Version 2.0" section below)

Copyright: Copyright 2021-2024 BUT Speech@FIT (original VBx project)

Upstream notice: https://github.com/FluidInference/FluidAudio/blob/4dbf4f9f9a5ff3a53ade848d7ba4e3df13db859b/ThirdPartyLicenses/vbx-LICENSE.md

## FluidInference speaker-diarization-coreml (bundled model)

Luxel bundles the `FluidInference/speaker-diarization-coreml` Core ML models
(based on `pyannote/speaker-diarization-community-1` and WeSpeaker) in the app
at `Contents/Resources/Models/speaker-diarization` (vendored from
`Vendor/Models/speaker-diarization`) to power the "Identify Speakers" feature.
The exact model revision is
`1ed7a662fdc7109e36d822db793ee6eebdaf8594`. The model is installed from the
app bundle only; Luxel never downloads it.

License: Creative Commons Attribution 4.0 International (CC-BY-4.0), https://creativecommons.org/licenses/by/4.0/

Attribution: FluidInference; pyannote.audio contributors (Hervé Bredin et al.); WeSpeaker contributors. Luxel redistributes the model files unmodified.

Model card: https://huggingface.co/FluidInference/speaker-diarization-coreml

License terms and warranty disclaimer: https://creativecommons.org/licenses/by/4.0/legalcode.en

## FluidInference silero-vad-coreml (bundled model)

Luxel bundles `silero-vad-unified-256ms-v6.2.1.mlmodelc` from
`FluidInference/silero-vad-coreml` at revision
`b419383c55c110e2c9271fa6ee0ea83d03c70d96` in
`Contents/Resources/Models/voice-activity-detection`. The model performs local
voice activity detection and is never downloaded at runtime.

License: MIT License

Copyright: Copyright (c) 2020-present Silero Team

Model card: https://huggingface.co/FluidInference/silero-vad-coreml

Upstream: https://github.com/snakers4/silero-vad

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## aufklarer/DeepFilterNet3-CoreML (bundled model)

Luxel bundles the `aufklarer/DeepFilterNet3-CoreML` model at revision
`937bad9811f1ffc1a06ea0d676461b080b2bdc93` in
`Contents/Resources/Models/studio-voice` for local Studio Voice export.

License: Apache License 2.0 (selected for the dual-licensed DeepFilterNet model
weights and the Core ML conversion; full text reproduced below)

Base model: Rikorose/DeepFilterNet3

Model card: https://huggingface.co/aufklarer/DeepFilterNet3-CoreML

## soniqo/speech-swift (adapted runtime)

Luxel includes a modified, narrow adaptation of the DeepFilterNet3 signal
processing code from `soniqo/speech-swift` v0.0.26 at revision
`f9af2f34d196eacca85d13fe508d8ed71919671f`. The adaptation removes MLX,
downloader, cache, and unrelated speech-model dependencies; it loads only the
explicit model and auxiliary-data URLs supplied by Luxel and processes bounded
PCM windows.

License: Apache License 2.0 (full text reproduced below)

Upstream: https://github.com/soniqo/speech-swift

## ZHKKKe/MODNet (bundled model)

Luxel bundles the video-adapted `modnet_webcam_portrait_matting.ckpt` from
ZHKKKe/MODNet, converted to an FP16 Core ML ML Program, at
`Contents/Resources/Models/modnet`. The source checkpoint has SHA-256
`913b82b66558db39b6286c150f809017d7528c872b156eb14333c9c6cb52108b` and
the upstream source is pinned to commit
`28165a451e4610c9d77cfdf925a94610bb2810fb`.

License: Apache License 2.0 (full text reproduced below)

Copyright: Copyright 2020 Zhanghan Ke and contributors

Upstream: https://github.com/ZHKKKe/MODNet

Paper: Zhanghan Ke et al., "MODNet: Real-Time Trimap-Free Portrait Matting via
Objective Decomposition," https://arxiv.org/abs/2011.11961

Model use: Luxel performs inference locally. Camera frames are not uploaded,
and the converted model does not require networking at runtime.

## Apache License, Version 2.0

The following license text applies to FluidAudio, NemoTextProcessing, VBx,
DeepFilterNet3-CoreML, the adapted speech-swift runtime, and MODNet.

                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      "control" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      "Source" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      "Object" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      "Work" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      "Derivative Works" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      "Contribution" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, "submitted"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as "Not a Contribution."

      "Contributor" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

   2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

   3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

   4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a "NOTICE" text file as part of its
          distribution, then any Derivative Works that You distribute must
          include a readable copy of the attribution notices contained
          within such NOTICE file, excluding those notices that do not
          pertain to any part of the Derivative Works, in at least one
          of the following places: within a NOTICE text file distributed
          as part of the Derivative Works; within the Source form or
          documentation, if provided along with the Derivative Works; or,
          within a display generated by the Derivative Works, if and
          wherever such third-party notices normally appear. The contents
          of the NOTICE file are for informational purposes only and
          do not modify the License. You may add Your own attribution
          notices within Derivative Works that You distribute, alongside
          or as an addendum to the NOTICE text from the Work, provided
          that such additional attribution notices cannot be construed
          as modifying the License.

      You may add Your own copyright statement to Your modifications and
      may provide additional or different license terms and conditions
      for use, reproduction, or distribution of Your modifications, or
      for any such Derivative Works as a whole, provided Your use,
      reproduction, and distribution of the Work otherwise complies with
      the conditions stated in this License.

   5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

   6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing the
      origin of the Work and reproducing the content of the NOTICE file.

   7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an "AS IS" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

   8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

   9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

   END OF TERMS AND CONDITIONS

   APPENDIX: How to apply the Apache License to your work.

      To apply the Apache License to your work, attach the following
      boilerplate notice, with the fields enclosed by brackets "[]"
      replaced with your own identifying information. (Don't include
      the brackets!)  The text should be enclosed in the appropriate
      comment syntax for the file format. We also recommend that a
      file or class name and description of purpose be included on the
      same "printed page" as the copyright notice for easier
      identification within third-party archives.

   Copyright [yyyy] [name of copyright owner]

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
