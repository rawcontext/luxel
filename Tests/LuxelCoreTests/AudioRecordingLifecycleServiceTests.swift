import Foundation
import LuxelCore
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

    private func makeHistory(store: InMemoryRecordingHistoryStore) -> RecordingHistoryService {
        RecordingHistoryService(
            store: store,
            fileSystem: AlwaysExistingFileSystem(),
            dateProvider: FixedDateProvider(Date(timeIntervalSince1970: 1_800_000_000)),
            mediaProbe: StaticMediaProbe(result: .playable)
        )
    }

    private func makeRequest() throws -> AudioRecordingRequest {
        try AudioRecordingRequest(
            outputFileURL: URL(fileURLWithPath: "/tmp/audio.m4a"),
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

private struct FixedDateProvider: DateProvider {
    let date: Date

    init(_ date: Date) {
        self.date = date
    }

    func now() -> Date {
        date
    }
}

private struct AlwaysExistingFileSystem: FileSystem {
    func fileExists(at url: URL) -> Bool {
        true
    }

    func createDirectory(at url: URL) throws {}

    func copyFile(from sourceURL: URL, to destinationURL: URL) throws {}

    func removeFile(at url: URL) throws {}

    func trashItem(at url: URL) throws {}
}
