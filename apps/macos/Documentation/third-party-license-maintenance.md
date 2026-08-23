# Third-Party License Maintenance

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
