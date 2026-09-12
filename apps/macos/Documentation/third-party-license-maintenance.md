# Third-Party License Maintenance

Luxel's original code is MIT licensed at the monorepo root. Vendored and adapted
third-party code and model files keep their existing licenses. Both signed app
builds include `LICENSE.txt` and `ThirdPartyLicenses.md` in their resources.

## MIT distribution review (2026-09-11)

The pinned distribution uses the following licenses. None requires Luxel's
original code to adopt a copyleft license; distribution still requires the
notices and conditions for each component.

| Components | License and retained obligations |
| --- | --- |
| libvpx, Opus, SVT-AV1 and its embedded components, fastcluster | BSD variants; preserve copyright, license, disclaimer, non-endorsement, and applicable patent grants. The Clear BSD license itself grants no patent rights. |
| FluidAudio, NemoTextProcessing, VBx, DeepFilterNet, adapted speech-swift runtime, MODNet | Apache-2.0; retain license, attribution and NOTICE contents, mark adapted files, and retain patent terms. |
| Speaker diarization models | CC-BY-4.0; retain model attribution, provenance, license link and modification status. These model files are not relicensed as MIT. |
| Silero VAD | MIT; retain its copyright and permission notice. |
| Rust crates linked by NemoTextProcessing | MIT, Apache-2.0, and Unicode-3.0; the exact pinned crate notices are included under NemoTextProcessing in the ledger. |

The review covers the native artifact manifest, pinned FluidAudio package and
its static binary target, adapted runtime source, and all four bundled model
manifests. The CLI's separate notice generator covers both macOS Cargo target
graphs and rejects unreviewed license expressions during packaging.

Sources: [Apache redistribution guidance](https://www.apache.org/foundation/license-faq#Distribute-changes),
[CC-BY-4.0 conditions](https://creativecommons.org/licenses/by/4.0/),
[MIT terms](https://opensource.org/license/mit), and
[Unicode terms](https://www.unicode.org/license.txt). Component-specific source
revisions and license texts are recorded in the acknowledgements and manifests.

## Updating dependencies

Before distributing an additional third-party library or model, add its exact
upstream license text, copyright notice, source, and required attribution to
`THIRD_PARTY_LICENSES.md`. The shipped acknowledgments file must contain only
customer-facing legal notices and attribution.

Vendored codecs must also pass `CodecLicensePolicy`. Add one structured entry
per codec using a `## Dependency: <dependency-id>` heading followed by `Name`,
`License`, `Copyright`, and `License Text` fields so the release gate can
validate the ledger against the codec dependency manifest. Treat compiled
third-party code inside a codec archive as a separate dependency entry even
when upstream distributes it in the same source tree.

Rebuild all native codecs through `Vendor/build-native-codecs.sh` with the
repository-pinned CMake 4.4.2 and Xcode 26.6 toolchain. The full aggregate build
is the only command allowed to regenerate `Vendor/Artifacts/manifest.json`,
because its global provenance applies to all three XCFrameworks. The narrower
`Vendor/build-webm-codecs.sh` rebuilds Opus and VPX and then audits them against
the committed manifest without rewriting the untouched SVT-AV1 provenance.

The auditor independently locks the exact toolchain, source identities,
library and header hashes and byte counts, complete license provenance fields,
normalized archive metadata, arm64 macOS 26 deployment target, runtime
versions, and canonical customer-facing codec notice sections. Run
`Scripts/check-codec-licenses.sh` to execute both its negative mutation suite
and the Swift license-policy gate. Running the full aggregate build a second
time must leave the manifest and every XCFramework byte unchanged.

When a Swift package is added or updated, inspect its target graph and bundled
source for transitive license notices. Update the acknowledgments inventory and
its regression test in the same change.

FluidAudio updates require an additional binary-target audit. Record the exact
FluidAudio tag and commit, every release-asset checksum in its package manifest,
and the notices for statically linked targets such as NemoTextProcessing.

Bundled models must have an immutable upstream revision, complete artifact list,
per-file SHA-256 values, total byte count, tree digest, license and notice, and
their complete input/output contract. Run the four source auditors before
building:

```sh
Scripts/audit-speaker-diarization-model.sh Vendor/Models/speaker-diarization
Scripts/audit-studio-voice-model.sh Vendor/Models/studio-voice
Scripts/audit-voice-activity-detection-model.sh Vendor/Models/voice-activity-detection
Scripts/audit-modnet-model.sh Vendor/Models/modnet
```

The signed development and Mac App Store build scripts run the native-codec
artifact/license gate and all four model source audits before compilation. They
repeat the model audits after assembly. MODNet conversion inputs live in
`Vendor/Models/modnet-tools/requirements.in`; regenerate the hashed lock with
the pinned uv/Python toolchain and run conversion twice to confirm that graph,
weights, normalized metadata, manifest, and fixtures do not drift.
