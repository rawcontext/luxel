import Foundation
import LuxelCore
import Testing

@testable import LuxelPresentation

@MainActor
@Suite("Automatic recording title UI")
struct LuxelEditorAutomaticTitleTests {
    @Test("a transcript started before the rename still appears in the editor")
    func pendingTranscriptSurvivesRename() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "LuxelPendingTitle-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let date = Date()
        let url = RecordingFileLayout.mediaURL(in: root, date: date, title: "Audio recording", fileExtension: "m4a")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: url)
        let recording = try RecordingDocumentStore().create(
            for: PastRecording(fileURL: url, name: "Audio recording", date: date), captureKind: "audio")
        let service = PendingTitleTranscriptService()
        let model = LuxelEditorModel(
            metadataReader: TitleTestMetadataReader(), audioTranscriptService: service,
            speechRecognitionAuthorizationService: TitleTestSpeechAuthorization())
        await model.open(fileURL: url, outputDirectory: root)
        await service.waitForRequest()
        let renamed = try RecordingDocumentStore().applyingAutomaticTitle("Early generated title", to: recording)
        model.applyAutomaticRecordingRename(from: url, to: renamed.primaryMediaURL)
        let span = try TimedTranscriptSpan(id: "one", text: "Transcript after rename", start: 0, end: 0.5)
        let transcript = try TurnSegmentedTranscript(
            spans: [span],
            turns: [TranscriptTurn(id: "turn", spanIDs: [span.id], start: 0, end: 0.5, text: span.text)],
            localeIdentifier: "en_US")
        await service.finish(transcript)
        for _ in 0..<200 where model.isTranscriptExtractionActive { await Task.yield() }
        #expect(model.transcript == transcript)
        #expect(!model.isTranscriptExtractionActive)
        #expect(model.source?.fileURL == renamed.primaryMediaURL)
    }

    @Test("an open editor adopts the new filename immediately and preserves its trim")
    func visibleFilenameUpdates() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "LuxelTitleUI-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let date = Date()
        let url = RecordingFileLayout.mediaURL(in: root, date: date, title: "Audio recording", fileExtension: "m4a")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: url)
        let recording = try RecordingDocumentStore().create(
            for: PastRecording(fileURL: url, name: "Audio recording", date: date), captureKind: "audio")
        let id = try #require(recording.bundleManifest?.organization?.id)
        RecordingDocumentStore.setTitlePending(true, id: id)
        defer { RecordingDocumentStore.setTitlePending(false, id: id) }
        let model = LuxelEditorModel(metadataReader: TitleTestMetadataReader())
        await model.open(fileURL: url, outputDirectory: root)
        model.trimStart = 0.1
        model.trimEnd = 0.9
        #expect(!model.canExport)

        let renamed = try RecordingDocumentStore().applyingAutomaticTitle("Checkout validation", to: recording)
        model.applyAutomaticRecordingRename(from: url, to: renamed.primaryMediaURL)
        RecordingDocumentStore.setTitlePending(false, id: id)
        model.refreshAutomaticTitleState(for: renamed.primaryMediaURL)

        #expect(model.source?.fileURL == renamed.primaryMediaURL)
        #expect(model.source?.fileURL.lastPathComponent.contains("Checkout validation") == true)
        #expect(model.trimStart == 0.1)
        #expect(model.trimEnd == 0.9)
        #expect(model.outputDirectory == renamed.primaryMediaURL.deletingLastPathComponent().appending(path: "Exports"))
        #expect(model.canExport)
    }
}

private actor PendingTitleTranscriptService: AudioTranscriptService {
    private var result: CheckedContinuation<TurnSegmentedTranscript?, any Error>?
    private var started: CheckedContinuation<Void, Never>?

    func transcript(for request: AudioTranscriptRequest) async throws -> TurnSegmentedTranscript? {
        try await withCheckedThrowingContinuation {
            result = $0
            started?.resume()
            started = nil
        }
    }

    func waitForRequest() async {
        if result != nil { return }
        await withCheckedContinuation { started = $0 }
    }

    func finish(_ transcript: TurnSegmentedTranscript) {
        result?.resume(returning: transcript)
        result = nil
    }
}

private struct TitleTestSpeechAuthorization: SpeechRecognitionAuthorizationService {
    func currentAuthorizationState() async -> SpeechRecognitionAuthorizationState { .authorized }
    func requestAuthorization() async -> SpeechRecognitionAuthorizationState { .authorized }
}

private struct TitleTestMetadataReader: MediaMetadataReader {
    func readSourceMedia(at fileURL: URL) async throws -> SourceMedia {
        try SourceMedia.audioOnly(fileURL: fileURL, duration: 1)
    }
}
