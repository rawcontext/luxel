import Foundation
import LuxelCore
import LuxelTestSupport
import Testing

@Suite("Audio recording lifecycle service")
struct AudioRecordingLifecycleServiceTests {
    @Test("start persists active audio recording before recorder starts")
    func startPersistsActiveAudioRecordingBeforeRecorderStarts() async throws {
        let store = InMemoryRecordingHistoryStore()
        let recorder = SpyAudioRecorder {
            #expect(store.activeRecording?.fileURL == URL(fileURLWithPath: "/tmp/audio.m4a"))
            #expect(store.activeRecording?.options.isAudioOnly == true)
        }
        let history = makeHistory(store: store)
        let service = AudioRecordingLifecycleService(recorder: recorder, history: history)

        let activeRecording = try await service.startRecording(
            try makeRequest(),
            name: "Voice Note"
        )

        #expect(activeRecording.name == "Voice Note")
        #expect(activeRecording.options.isAudioOnly)
        #expect(recorder.startedRequests == [try makeRequest()])
    }

    @Test("start clears active audio recording when recorder fails")
    func startClearsActiveAudioRecordingWhenRecorderFails() async throws {
        let store = InMemoryRecordingHistoryStore()
        let recorder = SpyAudioRecorder(startError: StubAudioRecorderError.startFailed)
        let service = AudioRecordingLifecycleService(
            recorder: recorder,
            history: makeHistory(store: store)
        )

        await #expect(throws: StubAudioRecorderError.startFailed) {
            try await service.startRecording(try makeRequest())
        }
        #expect(store.activeRecording == nil)
    }

    @Test("audio recording uses staging and finalizes to destination")
    func audioRecordingUsesStagingAndFinalizesToDestination() async throws {
        let finalURL = URL(fileURLWithPath: "/tmp/final/audio.m4a")
        let stagingURL = URL(fileURLWithPath: "/tmp/staging/audio.m4a")
        let store = InMemoryRecordingHistoryStore()
        let recorder = SpyAudioRecorder()
        let fileSystem = AudioRecordingOutputFileSystem(existingFiles: [stagingURL])
        let history = makeHistory(store: store, fileSystem: fileSystem)
        let service = AudioRecordingLifecycleService(
            recorder: recorder,
            history: history,
            outputFinalizer: FileSystemRecordingOutputFinalizer(fileSystem: fileSystem)
        )
        let request = try makeRequest(outputFileURL: finalURL)

        let activeRecording = try await service.startRecording(
            request,
            name: "Voice Note",
            outputPlan: RecordingOutputFinalizationPlan(
                stagingFileURL: stagingURL,
                finalFileURL: finalURL
            )
        )
        let recording = try await service.stopRecording()

        #expect(activeRecording.fileURL == finalURL)
        #expect(recorder.startedRequests.map(\.outputFileURL) == [stagingURL])
        #expect(recording.fileURL == finalURL)
        #expect(store.recordings == [recording])
        #expect(
            fileSystem.movedFiles == [
                AudioRecordingOutputMove(sourceURL: stagingURL, destinationURL: finalURL)
            ])
    }

    @Test("stop clears active audio recording when output finalization has no file")
    func stopClearsActiveAudioRecordingWhenOutputFinalizationHasNoFile() async throws {
        let finalURL = URL(fileURLWithPath: "/tmp/final/audio.m4a")
        let stagingURL = URL(fileURLWithPath: "/tmp/staging/audio.m4a")
        let store = InMemoryRecordingHistoryStore()
        let recorder = SpyAudioRecorder()
        let fileSystem = AudioRecordingOutputFileSystem(existingFiles: [])
        let service = AudioRecordingLifecycleService(
            recorder: recorder,
            history: makeHistory(store: store, fileSystem: fileSystem),
            outputFinalizer: FileSystemRecordingOutputFinalizer(fileSystem: fileSystem)
        )
        let request = try makeRequest(outputFileURL: finalURL)

        _ = try await service.startRecording(
            request,
            outputPlan: RecordingOutputFinalizationPlan(
                stagingFileURL: stagingURL,
                finalFileURL: finalURL
            )
        )

        await #expect(
            throws: RecordingLifecycleError.outputFinalizationFailed(
                "No recording output was produced. Try recording again."
            )
        ) {
            try await service.stopRecording()
        }
        #expect(store.activeRecording == nil)
        #expect(store.recordings.isEmpty)
        #expect(recorder.stopCallCount == 1)
        #expect(fileSystem.movedFiles.isEmpty)
    }

    @Test("stop moves active audio recording into history")
    func stopMovesActiveAudioRecordingIntoHistory() async throws {
        let store = InMemoryRecordingHistoryStore()
        let recorder = SpyAudioRecorder()
        let history = makeHistory(store: store)
        let service = AudioRecordingLifecycleService(recorder: recorder, history: history)

        _ = try await service.startRecording(try makeRequest(), name: "Original")
        let recording = try await service.stopRecording(recordingName: "Finished")

        #expect(recording.name == "Finished")
        #expect(store.activeRecording == nil)
        #expect(store.recordings == [recording])
        #expect(recorder.stopCallCount == 1)
    }

    @Test("stop keeps active audio recording when recorder fails")
    func stopKeepsActiveAudioRecordingWhenRecorderFails() async throws {
        let store = InMemoryRecordingHistoryStore()
        let recorder = SpyAudioRecorder(stopError: StubAudioRecorderError.stopFailed)
        let history = makeHistory(store: store)
        let service = AudioRecordingLifecycleService(recorder: recorder, history: history)

        _ = try await service.startRecording(try makeRequest())

        await #expect(throws: StubAudioRecorderError.stopFailed) {
            try await service.stopRecording()
        }
        #expect(store.activeRecording != nil)
        #expect(store.recordings.isEmpty)
    }

    private func makeHistory(
        store: InMemoryRecordingHistoryStore,
        fileSystem: any FileSystem = AlwaysExistingFileSystem()
    ) -> RecordingHistoryService {
        RecordingHistoryService(
            store: store,
            fileSystem: fileSystem,
            dateProvider: RecordingLifecycleFixedDateProvider(
                date: Date(timeIntervalSince1970: 1_800_000_000)
            ),
            mediaProbe: StaticMediaProbe(result: .playable)
        )
    }

    private func makeRequest(
        outputFileURL: URL = URL(fileURLWithPath: "/tmp/audio.m4a")
    ) throws -> AudioRecordingRequest {
        try AudioRecordingRequest(
            outputFileURL: outputFileURL,
            audio: .microphone(deviceID: "mic-1")
        )
    }
}

private final class SpyAudioRecorder: AudioRecorder, @unchecked Sendable {
    private let onStart: () -> Void
    private let startError: (any Error)?
    private let stopError: (any Error)?
    private let lock = NSLock()
    private(set) var startedRequests: [AudioRecordingRequest] = []
    private(set) var stopCallCount = 0

    init(
        startError: (any Error)? = nil,
        stopError: (any Error)? = nil,
        onStart: @escaping () -> Void = {}
    ) {
        self.startError = startError
        self.stopError = stopError
        self.onStart = onStart
    }

    func startRecording(_ request: AudioRecordingRequest) async throws {
        lock.withLock {
            startedRequests.append(request)
        }
        onStart()

        if let startError {
            throw startError
        }
    }

    func stopRecording() async throws {
        lock.withLock {
            stopCallCount += 1
        }

        if let stopError {
            throw stopError
        }
    }
}

private enum StubAudioRecorderError: Error, Equatable {
    case startFailed
    case stopFailed
}

private typealias AudioRecordingOutputMove = RecordingLifecycleOutputMove
private typealias AudioRecordingOutputFileSystem = RecordingLifecycleOutputFileSystem
private typealias AlwaysExistingFileSystem = AlwaysExistingTestFileSystem
