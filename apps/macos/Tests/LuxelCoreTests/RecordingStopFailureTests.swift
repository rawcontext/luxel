import Foundation
import LuxelCore
import LuxelTestSupport
import Testing

@Suite("Recording stop failures")
struct RecordingStopFailureTests {
    @Test("writer diagnostics preserve error codes without exposing private metadata")
    func diagnosticsPreserveErrorCodes() {
        let error = NSError(
            domain: "AVFoundationErrorDomain", code: -11800,
            userInfo: [
                NSLocalizedDescriptionKey: "Private recording name",
                NSFilePathErrorKey: "/private/recording.mp4",
                NSUnderlyingErrorKey: NSError(domain: NSOSStatusErrorDomain, code: -16341)
            ]
        )
        let failure = RecordingStopFailure(stage: .finishingWriter, underlyingError: error)

        #expect(failure.diagnosticDescription.contains("stage=finishingWriter"))
        #expect(failure.diagnosticDescription.contains("error_domain=AVFoundationErrorDomain error_code=-11800"))
        #expect(
            failure.diagnosticDescription.contains("underlying_domain=NSOSStatusErrorDomain underlying_code=-16341")
        )
        #expect(!failure.diagnosticDescription.contains("Private recording name"))
        #expect(!failure.diagnosticDescription.contains("/private/recording.mp4"))
        #expect(failure.localizedDescription == "Recording stopped, but the video could not be saved.")
    }
}

extension RecordingLifecycleServiceTests {
    @Test(
        "terminal writer failures release recording state on the first stop",
        arguments: [RecordingStopFailure.Stage.finishingWriter, .composingSegments]
    )
    func terminalWriterFailuresReleaseState(stage: RecordingStopFailure.Stage) async throws {
        let store = InMemoryRecordingHistoryStore()
        let recorder = RecordingLifecycleRecorderSpy(
            stopError: RecordingStopFailure(
                stage: stage, underlyingError: NSError(domain: NSOSStatusErrorDomain, code: -16341)
            )
        )
        let protection = RecordingProtectionSpy()
        let scheduler = RecordingLifecycleAutoStopScheduler()
        let replayEngine = RecordingLifecycleReplayEngineSpy()
        let replay = ReplayBufferService(engine: replayEngine)
        let configuration = try ReplayBufferConfiguration(
            bufferLength: 60, source: .displayWithCursor, frameRate: FrameRate(30)
        )
        try await replay.arm(configuration: configuration)
        let service = RecordingLifecycleService(
            recorder: recorder, history: makeHistory(store: store),
            autoStopScheduler: scheduler, replayBufferService: replay,
            terminationProtection: protection
        )
        let request = try makeRequest(schedule: RecordingSchedule(maxRecordedDuration: 60))
        _ = try await service.startRecording(request)

        await #expect(throws: RecordingStopFailure.self) { try await service.stopRecording() }

        #expect(recorder.stopCount == 1)
        #expect(store.activeRecording == nil)
        #expect(store.recordings.isEmpty)
        #expect(protection.events == [.recordingWillStart, .recordingDidEnd])
        #expect(replayEngine.commands() == [.arm(configuration), .pause(.recordingActive), .resume])
        #expect(scheduler.scheduledIntervals.count == 1)
        #expect(scheduler.isCanceled(at: 0))
        _ = try await service.startRecording(request)
        #expect(store.activeRecording != nil)
    }

    @Test("capture stop failures preserve active state for retry")
    func captureStopFailuresPreserveStateForRetry() async throws {
        let store = InMemoryRecordingHistoryStore()
        let recorder = RecordingLifecycleRecorderSpy(
            stopError: RecordingStopFailure(
                stage: .stoppingCapture, underlyingError: RecordingLifecycleRecorderError.stopFailed
            )
        )
        let protection = RecordingProtectionSpy()
        let service = RecordingLifecycleService(
            recorder: recorder, history: makeHistory(store: store), terminationProtection: protection
        )
        let active = try await service.startRecording(makeRequest())

        for _ in 0..<2 {
            await #expect(throws: RecordingStopFailure.self) { try await service.stopRecording() }
            #expect(store.activeRecording == active)
        }
        #expect(recorder.stopCount == 2)
        #expect(protection.events == [.recordingWillStart])
    }

    @Test("auto stop publishes terminal failure instead of leaving the UI recording")
    func autoStopPublishesTerminalFailure() async throws {
        let store = InMemoryRecordingHistoryStore()
        let recorder = RecordingLifecycleRecorderSpy(
            stopError: RecordingStopFailure(
                stage: .finishingWriter, underlyingError: RecordingLifecycleRecorderError.stopFailed
            )
        )
        let scheduler = RecordingLifecycleAutoStopScheduler()
        let service = makeService(store: store, recorder: recorder, autoStopScheduler: scheduler)
        var events = service.autoStopResults.makeAsyncIterator()
        _ = try await service.startRecording(makeRequest(schedule: RecordingSchedule(maxRecordedDuration: 60)))

        await scheduler.fireScheduledTask(at: 0)

        let result = try #require(await events.next())
        #expect(result.fileURL == (try makeRequest()).outputFileURL)
        #expect(throws: RecordingStopFailure.self) { try result.result.get() }
        #expect(store.activeRecording == nil)
        #expect(scheduler.scheduledIntervals.count == 1)
    }
}
