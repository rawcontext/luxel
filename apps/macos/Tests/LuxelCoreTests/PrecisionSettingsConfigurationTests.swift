import Foundation
import Testing

@Suite("Precision settings configuration")
struct PrecisionSettingsConfigurationTests {
    @Test("presents one feature card without model implementation details")
    func presentsOneFeatureCard() throws {
        let sourceURL = packageRoot.appending(
            path: "Sources/LuxelApp/Settings/Views/LuxelSettingsView+Transcripts.swift"
        )
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("precisionTranscriptionCard"))
        #expect(source.contains("Toggle(\"Precision Transcription\", isOn: precisionToggleBinding)"))
        #expect(source.contains("LuxelGlassSwitchToggleStyle(showsLabel: false)"))
        #expect(source.contains(".accessibilityLabel(\"Precision Transcription\")"))
        #expect(source.contains("Higher-accuracy local transcription. Requires a 483 MB download."))
        #expect(!source.contains("\"Local Models\""))
        #expect(!source.contains("Parakeet TDT"))
        #expect(!source.contains("\"Model Card\""))
        #expect(!source.contains("CC-BY-4.0"))
        #expect(!source.contains("Download and Enable..."))
        #expect(!source.contains("Download Precision Transcription?"))
        #expect(!source.contains("Remove Precision Transcription?"))
        #expect(source.contains("model.installAndEnablePrecisionTranscription()"))
        #expect(source.contains("model.removePrecisionModel()"))

        let localizationCatalog = try String(
            contentsOf: packageRoot.appending(
                path: "Sources/LuxelCore/Resources/Localizable.xcstrings"
            ),
            encoding: .utf8
        )
        let precisionRuntime = try String(
            contentsOf: packageRoot.appending(
                path: "Sources/LuxelCore/Infrastructure/Transcripts/PrecisionTranscription.swift"
            ),
            encoding: .utf8
        )
        #expect(!localizationCatalog.localizedCaseInsensitiveContains("parakeet"))
        #expect(!precisionRuntime.contains("\"Parakeet"))
    }
}

private let packageRoot = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
