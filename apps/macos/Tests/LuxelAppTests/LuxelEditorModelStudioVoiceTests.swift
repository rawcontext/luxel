import Foundation
import Testing

@testable import LuxelPresentation

extension LuxelEditorModelTests {
    @Test("Studio Voice resets per source, participates in undo, and reaches export requests")
    func studioVoiceStateAndExportPropagation() async throws {
        let exporter = SpyMediaExporter()
        let model = makeModel(exporter: exporter)

        await model.open(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            outputDirectory: URL(fileURLWithPath: "/tmp")
        )

        #expect(!model.studioVoiceEnabled)
        #expect(model.canUseStudioVoice)

        model.setStudioVoiceEnabled(true)
        #expect(model.studioVoiceEnabled)

        model.undoEditorChange()
        #expect(!model.studioVoiceEnabled)

        model.redoEditorChange()
        #expect(model.studioVoiceEnabled)

        model.startExport()
        while model.isExporting {
            try await Task.sleep(for: .milliseconds(10))
        }

        let captured = await exporter.capturedExports()
        #expect(captured.first?.request.studioVoiceEnabled == true)

        await model.open(
            fileURL: URL(fileURLWithPath: "/tmp/next.mp4"),
            outputDirectory: URL(fileURLWithPath: "/tmp")
        )
        #expect(!model.studioVoiceEnabled)
        #expect(!model.canUndoEditorChange)
    }

    @Test("Studio Voice stays stored while audio is excluded but is ineffective")
    func studioVoiceAudioExclusion() async throws {
        let model = makeModel()

        await model.open(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            outputDirectory: URL(fileURLWithPath: "/tmp")
        )
        model.setStudioVoiceEnabled(true)
        model.setIncludesAudio(false)
        let request = try model.makeExportRequest(
            source: #require(model.source),
            format: .mp4
        )

        #expect(model.studioVoiceEnabled)
        #expect(!model.canUseStudioVoice)
        #expect(!request.shouldApplyStudioVoice)

        model.setIncludesAudio(true)
        #expect(model.studioVoiceEnabled)
        #expect(model.canUseStudioVoice)
    }
}
