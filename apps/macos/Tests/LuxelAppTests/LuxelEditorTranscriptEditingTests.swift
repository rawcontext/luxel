import Foundation
import LuxelCore
import Testing

@testable import LuxelPresentation

@MainActor
@Suite("Luxel editor transcript editing")
struct LuxelEditorTranscriptEditingTests {
    @Test("sentence cuts are non-destructive undoable and exported for audio and video")
    func sentenceCutsApplyToAudioAndVideo() async throws {
        let helper = LuxelEditorModelTests()
        let transcript = try editableTranscript()
        let sources = try [
            SourceMedia(
                fileURL: URL(fileURLWithPath: "/tmp/video.mp4"),
                duration: 12,
                pixelSize: PixelSize(width: 1280, height: 720),
                nominalFrameRate: FrameRate(30),
                hasAudio: true
            ),
            SourceMedia.audioOnly(
                fileURL: URL(fileURLWithPath: "/tmp/audio.m4a"),
                duration: 12
            )
        ]

        for source in sources {
            let model = helper.makeModel(metadataReader: StubMetadataReader(source: source))
            await model.open(
                fileURL: source.fileURL,
                outputDirectory: URL(fileURLWithPath: "/tmp")
            )
            model.transcript = transcript
            model.isTranscriptPanelVisible = true

            let originalTranscript = model.transcript
            let sentence = try #require(
                model.editableTranscriptSentences.first { $0.text == "Delete this." }
            )
            model.selectTranscriptSentence(sentence)
            model.deleteSelectedTranscriptSentence()

            #expect(model.transcript == originalTranscript)
            #expect(model.transcriptEditPlan.cuts.count == 1)
            #expect(model.visibleTranscriptSentences.map(\.text) == ["Keep.", "Remain."])
            #expect(try model.editedTimelineMapper.outputDuration == 11)
            let request = try model.makeExportRequest(source: source, format: model.format)
            #expect(request.editPlan == model.transcriptEditPlan)

            model.handlePlaybackTime(1.25)
            #expect(model.currentPlaybackTime == 2.25)

            model.undoEditorChange()
            #expect(model.transcriptEditPlan == .empty)
            #expect(model.visibleTranscriptSentences.count == 3)

            model.redoEditorChange()
            #expect(model.transcriptEditPlan.cuts.count == 1)
            #expect(model.visibleTranscriptSentences.map(\.text) == ["Keep.", "Remain."])
        }
    }

    @Test("deleting all retained media reports a no-op")
    func sentenceCutCannotRemoveEditableRange() async throws {
        let helper = LuxelEditorModelTests()
        let sourceURL = URL(fileURLWithPath: "/tmp/video.mp4")
        let source = try SourceMedia(
            fileURL: sourceURL,
            duration: 1,
            pixelSize: PixelSize(width: 1280, height: 720),
            nominalFrameRate: FrameRate(30),
            hasAudio: true
        )
        let model = helper.makeModel(metadataReader: StubMetadataReader(source: source))
        await model.open(fileURL: sourceURL, outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.transcript = try helper.sampleTranscript(source: .system)
        let sentence = try #require(model.editableTranscriptSentences.first)

        model.selectTranscriptSentence(sentence)
        model.deleteSelectedTranscriptSentence()

        #expect(model.transcriptEditPlan == .empty)
        #expect(model.transcriptEditStatusMessage == "Keep at least part of the recording.")
    }

    @Test("shift selection cuts one contiguous sentence group")
    func shiftSelectionCutsSentenceGroup() async throws {
        let helper = LuxelEditorModelTests()
        let sourceURL = URL(fileURLWithPath: "/tmp/video.mp4")
        let source = try SourceMedia(
            fileURL: sourceURL,
            duration: 12,
            pixelSize: PixelSize(width: 1280, height: 720),
            nominalFrameRate: FrameRate(30),
            hasAudio: true
        )
        let model = helper.makeModel(metadataReader: StubMetadataReader(source: source))
        await model.open(fileURL: sourceURL, outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.transcript = try editableTranscript()
        let sentences = model.editableTranscriptSentences

        model.selectTranscriptSentence(sentences[0])
        model.selectTranscriptSentence(sentences[1], extendingSelection: true)

        #expect(model.selectedTranscriptSentenceIDs == Set(sentences[0...1].map(\.id)))
        model.deleteSelectedTranscriptSentence()
        #expect(model.transcriptEditPlan.cuts.count == 1)
        #expect(model.transcriptEditPlan.cuts[0].sourceRange == (try TimeRange(start: 0, end: 2)))
        #expect(model.visibleTranscriptSentences.map(\.text) == ["Remain."])
    }

    @Test("preview build failure blocks cut-enabled export until undo")
    func previewBuildFailureBlocksExport() async throws {
        let helper = LuxelEditorModelTests()
        let sourceURL = URL(fileURLWithPath: "/tmp/missing-transcript-edit-source.mp4")
        let source = try SourceMedia(
            fileURL: sourceURL,
            duration: 12,
            pixelSize: PixelSize(width: 1280, height: 720),
            nominalFrameRate: FrameRate(30),
            hasAudio: true
        )
        let model = helper.makeModel(metadataReader: StubMetadataReader(source: source))
        await model.open(fileURL: sourceURL, outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.transcript = try editableTranscript()
        let sentence = try #require(
            model.editableTranscriptSentences.first { $0.text == "Delete this." }
        )

        model.selectTranscriptSentence(sentence)
        model.deleteSelectedTranscriptSentence()
        #expect(!model.canExport)

        for _ in 0..<100 where model.previewCompositionTask != nil {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(!model.isEditedPreviewReady)
        #expect(!model.canExport)
        #expect(
            model.transcriptEditStatusMessage
                == "Edited preview unavailable; undo the cut to export."
        )
        model.startExport()
        #expect(model.status == .ready)

        model.undoEditorChange()
        #expect(model.transcriptEditPlan == .empty)
        #expect(model.isEditedPreviewReady)
        #expect(model.canExport)
    }

    private func editableTranscript() throws -> TurnSegmentedTranscript {
        let spans = try [
            TimedTranscriptSpan(id: "keep", text: "Keep.", start: 0, end: 0.8),
            TimedTranscriptSpan(id: "delete", text: "Delete", start: 1, end: 1.4),
            TimedTranscriptSpan(id: "this", text: "this.", start: 1.5, end: 2),
            TimedTranscriptSpan(id: "remain", text: "Remain.", start: 2.2, end: 3)
        ]
        return try TurnSegmentedTranscript(
            spans: spans,
            turns: [
                TranscriptTurn(
                    id: "turn",
                    spanIDs: spans.map(\.id),
                    start: 0,
                    end: 3,
                    text: "Keep. Delete this. Remain."
                )
            ],
            localeIdentifier: "en_US"
        )
    }
}
