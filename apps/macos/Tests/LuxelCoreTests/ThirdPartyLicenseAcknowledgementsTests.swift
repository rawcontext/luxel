import Foundation
import LuxelTestSupport
import Testing

private let expectedThirdPartyComponentHeadings = [
    "## Dependency: libvpx",
    "## Dependency: libopus",
    "## Dependency: svt-av1",
    "## Dependency: svt-av1-aom",
    "## Dependency: svt-av1-dav1d",
    "## Dependency: svt-av1-fastfeat",
    "## FluidAudio",
    "## NemoTextProcessing (included by FluidAudio)",
    "## fastcluster (included by FluidAudio)",
    "## VBx (included by FluidAudio)",
    "## FluidInference speaker-diarization-coreml (bundled model)",
    "## FluidInference silero-vad-coreml (bundled model)",
    "## aufklarer/DeepFilterNet3-CoreML (bundled model)",
    "## soniqo/speech-swift (adapted runtime)",
    "## ZHKKKe/MODNet (bundled model)",
    "## Build-generated Swift resource accessors"
]

private let expectedThirdPartyResourcePaths = [
    "Vendor/Artifacts/CVPX.xcframework",
    "Vendor/Artifacts/COpus.xcframework",
    "Vendor/Artifacts/CSVTAV1.xcframework",
    "Vendor/Models/speaker-diarization",
    "Vendor/Models/voice-activity-detection",
    "Vendor/Models/studio-voice",
    "Vendor/Models/modnet",
    "Vendor/Models/speaker-diarization/LICENSE.txt",
    "Vendor/Models/speaker-diarization/NOTICE.md",
    "Vendor/Models/speaker-diarization/model-manifest.json",
    "Vendor/Models/studio-voice/LICENSE.txt",
    "Vendor/Models/studio-voice/NOTICE.md",
    "Vendor/Models/studio-voice/manifest.json"
]

@Suite("Third-party license acknowledgements")
struct ThirdPartyLicenseAcknowledgementsTests {
    @Test("acknowledgements cover every shipped third-party component")
    func acknowledgementsCoverEveryShippedThirdPartyComponent() throws {
        let packageRoot = try testPackageRootURL()
        let markdown = try String(
            contentsOf: packageRoot.appending(path: "THIRD_PARTY_LICENSES.md"),
            encoding: .utf8
        )
        let componentHeadings =
            markdown
            .components(separatedBy: .newlines)
            .filter { $0.hasPrefix("## ") && $0 != "## Apache License, Version 2.0" }

        #expect(componentHeadings == expectedThirdPartyComponentHeadings)

        let packageResolved = try JSONDecoder().decode(
            ResolvedPackage.self,
            from: Data(contentsOf: packageRoot.appending(path: "Package.resolved"))
        )
        #expect(Set(packageResolved.pins.map(\.identity)) == ["fluidaudio"])

        for path in expectedThirdPartyResourcePaths {
            #expect(FileManager.default.fileExists(atPath: packageRoot.appending(path: path).path))
        }
    }

    @Test("shipped acknowledgements contain no internal maintenance language")
    func shippedAcknowledgementsContainNoInternalMaintenanceLanguage() throws {
        let markdown = try String(
            contentsOf: testPackageRootURL().appending(path: "THIRD_PARTY_LICENSES.md"),
            encoding: .utf8
        )

        for internalText in [
            "## Maintenance Notes",
            "must pass Luxel's",
            "reviewed by product/legal",
            "tracked in docs/"
        ] {
            #expect(!markdown.contains(internalText))
        }
    }
}

private struct ResolvedPackage: Decodable {
    struct Pin: Decodable {
        let identity: String
    }

    let pins: [Pin]
}
