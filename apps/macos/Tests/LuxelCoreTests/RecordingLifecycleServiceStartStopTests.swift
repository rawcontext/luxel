import Foundation
import LuxelCore
import Testing

extension RecordingLifecycleServiceTests {
    @Test("start persists active recording before recorder starts")
    func startPersistsActiveRecordingBeforeRecorderStarts() async throws {
        let store = InMemoryRecordingHistoryStore()
        let recorder = RecordingLifecycleRecorderSpy {
            #expect(store.activeRecording?.name == "Manual Name")
        }
        let service = makeService(store: store, recorder: recorder)
        let request = try makeRequest()

        let activeRecording = try await service.startRecording(request, name: "Manual Name")

        #expect(activeRecording.fileURL == request.outputFileURL)
        #expect(activeRecording.name == "Manual Name")
        #expect(store.activeRecording == activeRecording)
        #expect(recorder.startCount == 1)
        #expect(recorder.stopCount == 0)
    }

    @Test("start clears active recording when recorder fails")
    func startClearsActiveRecordingWhenRecorderFails() async throws {
        let store = InMemoryRecordingHistoryStore()
        let recorder = RecordingLifecycleRecorderSpy(
            startError: RecordingLifecycleRecorderError.startFailed)
        let service = makeService(store: store, recorder: recorder)

        await #expect(throws: RecordingLifecycleRecorderError.startFailed) {
            try await service.startRecording(try makeRequest())
        }
        #expect(store.activeRecording == nil)
    }

    @Test("recording pauses and resumes replay buffer")
    func recordingPausesAndResumesReplayBuffer() async throws {
        let store = InMemoryRecordingHistoryStore()
        let recorder = RecordingLifecycleRecorderSpy()
        let replayEngine = RecordingLifecycleReplayEngineSpy()
        let replayBufferService = ReplayBufferService(engine: replayEngine)
        let replayConfiguration = try ReplayBufferConfiguration(
            bufferLength: 60,
            source: .displayWithCursor,
            frameRate: FrameRate(30)
        )
        try await replayBufferService.arm(configuration: replayConfiguration)
        let service = makeService(
            store: store,
            recorder: recorder,
            replayBufferService: replayBufferService
        )

        _ = try await service.startRecording(try makeRequest())
        _ = try await service.stopRecording()

        #expect(
            replayEngine.commands() == [
                .arm(replayConfiguration),
                .pause(.recordingActive),
                .resume
            ])
    }

    @Test("start waits for countdown before active recording snapshot")
    func startWaitsForCountdownBeforeActiveRecordingSnapshot() async throws {
        let store = InMemoryRecordingHistoryStore()
        let sleeper = RecordingLifecycleCountdownSleeperSpy {
            #expect(store.activeRecording == nil)
        }
        let recorder = RecordingLifecycleRecorderSpy {
            #expect(sleeper.sleepDurations == [3])
            #expect(store.activeRecording != nil)
        }
        let service = makeService(
            store: store,
            recorder: recorder,
            countdownSleeper: sleeper
        )
        let request = try makeRequest(schedule: RecordingSchedule(countdown: 3))

        _ = try await service.startRecording(request)

        #expect(sleeper.sleepDurations == [3])
        #expect(recorder.startCount == 1)
    }

    @Test("cancelled countdown leaves no active recording")
    func cancelledCountdownLeavesNoActiveRecording() async throws {
        let store = InMemoryRecordingHistoryStore()
        let sleeper = RecordingLifecycleCountdownSleeperSpy(error: CancellationError())
        let recorder = RecordingLifecycleRecorderSpy()
        let service = makeService(
            store: store,
            recorder: recorder,
            countdownSleeper: sleeper
        )

        await #expect(throws: CancellationError.self) {
            try await service.startRecording(try makeRequest(schedule: RecordingSchedule(countdown: 5)))
        }

        #expect(store.activeRecording == nil)
        #expect(recorder.startCount == 0)
    }

    @Test("start records to staging while returning final recording URL")
    func startRecordsToStagingWhileReturningFinalRecordingURL() async throws {
        let context = try makeStagedRecordingContext()

        let activeRecording = try await startStagedRecording(context)

        #expect(activeRecording.fileURL == context.finalURL)
        #expect(context.store.activeRecording?.fileURL == context.stagingURL)
        #expect(context.recorder.startedRequests.map(\.outputFileURL) == [context.stagingURL])
    }

    @Test("stop finalizes staged recording to final URL")
    func stopFinalizesStagedRecordingToFinalURL() async throws {
        let context = try makeStagedRecordingContext()

        _ = try await startStagedRecording(context)
        let recording = try await context.service.stopRecording(recordingName: "Finished")

        #expect(recording.fileURL == context.finalURL)
        #expect(context.store.activeRecording == nil)
        #expect(context.store.recordings == [recording])
        #expect(
            context.fileSystem.movedFiles == [
                RecordingLifecycleOutputMove(
                    sourceURL: context.stagingURL,
                    destinationURL: context.finalURL
                )
            ])
    }

    @Test("stop keeps staged recording when final move fails")
    func stopKeepsStagedRecordingWhenFinalMoveFails() async throws {
        let context = try makeStagedRecordingContext(
            moveError: RecordingLifecycleOutputError.moveFailed
        )

        _ = try await startStagedRecording(context)
        let recording = try await context.service.stopRecording()

        #expect(recording.fileURL == context.stagingURL)
        #expect(context.store.recordings == [recording])
        #expect(context.fileSystem.movedFiles.isEmpty)
    }

    @Test("stop clears active recording when output finalization has no file")
    func stopClearsActiveRecordingWhenOutputFinalizationHasNoFile() async throws {
        let context = try makeStagedRecordingContext(outputExists: false)

        _ = try await startStagedRecording(context)

        await #expect(
            throws: RecordingLifecycleError.outputFinalizationFailed(
                "No recording output was produced. Try recording again."
            )
        ) {
            try await context.service.stopRecording()
        }
        #expect(context.store.activeRecording == nil)
        #expect(context.store.recordings.isEmpty)
        #expect(context.recorder.stopCount == 1)
        #expect(context.fileSystem.movedFiles.isEmpty)
    }

    @Test("stop moves active recording into history after recorder stops")
    func stopMovesActiveRecordingIntoHistoryAfterRecorderStops() async throws {
        let store = InMemoryRecordingHistoryStore()
        let fileURL = URL(fileURLWithPath: "/tmp/luxel.mp4")
        let fileSystem = RecordingLifecycleStubFileSystem(existingFiles: [fileURL])
        let recorder = RecordingLifecycleRecorderSpy()
        let history = makeHistory(store: store, fileSystem: fileSystem)
        let service = RecordingLifecycleService(recorder: recorder, history: history)
        history.setCurrentRecording(
            fileURL: fileURL, name: "Active", options: RecordingOptions(frameRate: 30))

        let recording = try await service.stopRecording(recordingName: "Finished")

        #expect(recording.fileURL == fileURL)
        #expect(recording.name == "Finished")
        #expect(store.activeRecording == nil)
        #expect(store.recordings == [recording])
        #expect(recorder.stopCount == 1)
    }

    @Test("stop keeps active recording when recorder fails")
    func stopKeepsActiveRecordingWhenRecorderFails() async throws {
        let store = InMemoryRecordingHistoryStore()
        let recorder = RecordingLifecycleRecorderSpy(
            stopError: RecordingLifecycleRecorderError.stopFailed)
        let history = makeHistory(store: store)
        let service = RecordingLifecycleService(recorder: recorder, history: history)
        history.setCurrentRecording(
            fileURL: URL(fileURLWithPath: "/tmp/luxel.mp4"),
            name: "Active",
            options: RecordingOptions(frameRate: 30)
        )

        await #expect(throws: RecordingLifecycleRecorderError.stopFailed) {
            try await service.stopRecording()
        }
        #expect(store.activeRecording?.name == "Active")
        #expect(store.recordings.isEmpty)
    }

}

private struct StagedRecordingContext {
    let store: InMemoryRecordingHistoryStore
    let recorder: RecordingLifecycleRecorderSpy
    let fileSystem: RecordingLifecycleOutputFileSystem
    let service: RecordingLifecycleService
    let request: RecordingRequest
    let stagingURL: URL
    let finalURL: URL
}

extension RecordingLifecycleServiceTests {
    fileprivate func makeStagedRecordingContext(
        outputExists: Bool = true,
        moveError: (any Error)? = nil
    ) throws -> StagedRecordingContext {
        let store = InMemoryRecordingHistoryStore()
        let recorder = RecordingLifecycleRecorderSpy()
        let finalURL = URL(fileURLWithPath: "/tmp/final/luxel.mp4")
        let stagingURL = URL(fileURLWithPath: "/tmp/staging/luxel.mp4")
        let fileSystem = RecordingLifecycleOutputFileSystem(
            existingFiles: outputExists ? [stagingURL] : [],
            moveError: moveError
        )
        let service = RecordingLifecycleService(
            recorder: recorder,
            history: makeHistory(store: store, fileSystem: fileSystem),
            outputFinalizer: FileSystemRecordingOutputFinalizer(fileSystem: fileSystem)
        )
        return StagedRecordingContext(
            store: store,
            recorder: recorder,
            fileSystem: fileSystem,
            service: service,
            request: try makeRequest(outputFileURL: finalURL),
            stagingURL: stagingURL,
            finalURL: finalURL
        )
    }

    fileprivate func startStagedRecording(
        _ context: StagedRecordingContext
    ) async throws -> ActiveRecording {
        try await context.service.startRecording(
            context.request,
            outputPlan: RecordingOutputFinalizationPlan(
                stagingFileURL: context.stagingURL,
                finalFileURL: context.finalURL
            )
        )
    }
}
