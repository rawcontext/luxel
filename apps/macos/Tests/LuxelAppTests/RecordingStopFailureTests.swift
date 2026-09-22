import Foundation
import LuxelCore
import LuxelTestSupport
import Testing

@testable import LuxelApp

@Suite("Recording stop failure presentation")
@MainActor
struct RecordingStopFailurePresentationTests {
    @Test(
        "one stop clears the UI after terminal writer failure but preserves retryable capture",
        arguments: [RecordingStopFailure.Stage.stoppingCapture, .finishingWriter, .composingSegments]
    )
    func stopReconcilesRecordingState(stage: RecordingStopFailure.Stage) async throws {
        let failure = RecordingStopFailure(
            stage: stage, underlyingError: NSError(domain: NSOSStatusErrorDomain, code: -16341)
        )
        let store = InMemoryRecordingHistoryStore()
        let history = RecordingHistoryService(
            store: store, fileSystem: AlwaysExistingTestFileSystem(),
            dateProvider: SystemDateProvider(),
            mediaProbe: StaticMediaProbe(result: .playable)
        )
        let recorder = FailingStopRecorder(failure: failure)
        let model = LuxelMenuModel(
            settingsStore: StopFailureSettingsStore(), recordingHistoryService: history,
            recorder: recorder
        )
        let request = try RecordingRequest(
            target: .display(DisplayID(1)), outputFileURL: URL(fileURLWithPath: "/tmp/failed.mp4"),
            pixelSize: PixelSize(width: 640, height: 480), frameRate: FrameRate(30)
        )
        let active = try await model.recordingLifecycleService.startRecording(request)
        let previousState = RecordingMenuState.recording(active, RecordingMenuClock(startedAt: active.date))
        model.recordingState = previousState

        let action = await model.stopRecording()

        #expect(action == nil)
        #expect(recorder.stopCount == 1)
        #expect(model.recordingState == (failure.isTerminal ? RecordingMenuState.idle : previousState))
        #expect(model.canBeginRecordingStart == failure.isTerminal)
        #expect((store.activeRecording == nil) == failure.isTerminal)
        #expect(model.recordingActionErrorMessage == failure.localizedDescription)
    }
}

private struct StopFailureSettingsStore: SettingsStore {
    func load() throws -> AppSettings {
        AppSettings.defaults(recordingsDirectory: URL(fileURLWithPath: "/tmp/LuxelStopFailureTests"))
    }

    func save(_ settings: AppSettings) throws {}
}

private final class FailingStopRecorder: CaptureRecorder, @unchecked Sendable {
    let failure: RecordingStopFailure
    private(set) var stopCount = 0

    init(failure: RecordingStopFailure) { self.failure = failure }

    func startRecording(_ request: RecordingRequest) async throws {}
    func pauseRecording() async throws {}
    func resumeRecording() async throws {}
    func stopRecording() async throws {
        stopCount += 1
        throw failure
    }
}
