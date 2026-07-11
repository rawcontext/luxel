import AVFoundation
import Foundation
import LuxelCore
import Testing

@testable import LuxelPresentation

@MainActor
@Suite("Luxel editor transcript editing")
struct LuxelEditorTranscriptEditingTests {
    @Test("word selection respects transcript auto-play preference")
    func wordSelectionRespectsAutoPlayPreference() async throws {
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
        model.player = ImmediateSeekPlayer()
        model.transcript = try editableTranscript()
        let words = model.editableTranscriptWords

        model.selectTranscriptWord(words[0], autoPlay: false)
        await Task.yield()
        #expect(!model.playbackRequested)
        #expect(model.currentPlaybackTime == words[0].sourceRange.start)

        model.selectTranscriptWord(words[1])
        await Task.yield()
        #expect(model.playbackRequested)
        #expect(model.currentPlaybackTime == words[1].sourceRange.start)
    }

    @Test("word cuts are non-destructive undoable and exported for audio and video")
    func wordCutsApplyToAudioAndVideo() async throws {
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
            let word = try #require(
                model.editableTranscriptWords.first { $0.text == "Delete" }
            )
            model.selectTranscriptWord(word)
            #expect(model.deleteSelectedTranscriptWord())

            #expect(model.transcript == originalTranscript)
            #expect(model.transcriptEditPlan.cuts.count == 1)
            #expect(model.canUndoLastTranscriptCut)
            #expect(model.transcriptCutReviewItems.map(\.text) == ["Delete"])
            #expect(model.visibleTranscriptWords.map(\.text) == ["Keep.", "this.", "Remain."])
            #expect(try model.editedTimelineMapper.outputDuration == 11.6)
            let request = try model.makeExportRequest(source: source, format: model.format)
            #expect(request.editPlan == model.transcriptEditPlan)

            model.handlePlaybackTime(1.25)
            #expect(model.currentPlaybackTime == 1.65)

            model.undoLastTranscriptCut()
            #expect(model.transcriptEditPlan == .empty)
            #expect(model.visibleTranscriptWords.count == 4)
            #expect(!model.canUndoLastTranscriptCut)
            #expect(model.transcriptEditStatusMessage == nil)

            model.redoEditorChange()
            #expect(model.transcriptEditPlan.cuts.count == 1)
            #expect(model.visibleTranscriptWords.map(\.text) == ["Keep.", "this.", "Remain."])
        }
    }

    @Test("removed ranges can be reviewed and restored individually")
    func removedRangesCanBeRestoredIndividually() async throws {
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

        let delete = try #require(model.editableTranscriptWords.first { $0.text == "Delete" })
        model.selectTranscriptWord(delete)
        #expect(model.deleteSelectedTranscriptWord())
        let firstCutID = try #require(model.transcriptCutReviewItems.first?.id)

        let remain = try #require(model.visibleTranscriptWords.first { $0.text == "Remain." })
        model.selectTranscriptWord(remain)
        #expect(model.deleteSelectedTranscriptWord())
        #expect(model.transcriptCutReviewItems.map(\.text) == ["Delete", "Remain."])

        model.restoreTranscriptCut(id: firstCutID)

        #expect(model.transcriptCutReviewItems.map(\.text) == ["Remain."])
        #expect(model.visibleTranscriptWords.map(\.text) == ["Keep.", "Delete", "this."])

        model.undoEditorChange()
        #expect(model.transcriptCutReviewItems.map(\.text) == ["Delete", "Remain."])
    }

    @Test("deleting all retained media reports a no-op")
    func wordCutCannotRemoveEditableRange() async throws {
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
        let words = model.editableTranscriptWords
        let firstWord = try #require(words.first)
        let lastWord = try #require(words.last)

        model.selectTranscriptWord(firstWord)
        model.selectTranscriptWord(lastWord, extendingSelection: true)
        model.deleteSelectedTranscriptWord()

        #expect(model.transcriptEditPlan == .empty)
        #expect(model.transcriptEditStatusMessage == "Keep at least part of the recording.")
    }

    @Test("shift selection cuts one contiguous word group")
    func shiftSelectionCutsWordGroup() async throws {
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
        let words = model.editableTranscriptWords

        model.selectTranscriptWord(words[1])
        model.selectTranscriptWord(words[2], extendingSelection: true)

        #expect(model.selectedTranscriptWordIDs == Set(words[1...2].map(\.id)))
        model.deleteSelectedTranscriptWord()
        #expect(model.transcriptEditPlan.cuts.count == 1)
        #expect(model.transcriptEditPlan.cuts[0].sourceRange == (try TimeRange(start: 1, end: 2)))
        #expect(model.visibleTranscriptWords.map(\.text) == ["Keep.", "Remain."])
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
        let word = try #require(
            model.editableTranscriptWords.first { $0.text == "Delete" }
        )

        model.selectTranscriptWord(word)
        model.deleteSelectedTranscriptWord()
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

private final class ImmediateSeekPlayer: AVPlayer, @unchecked Sendable {
    override func seek(
        to time: CMTime,
        toleranceBefore: CMTime,
        toleranceAfter: CMTime,
        completionHandler: @escaping @Sendable (Bool) -> Void
    ) {
        completionHandler(true)
    }
}
