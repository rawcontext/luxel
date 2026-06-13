import Foundation
import LuxelCore
import Testing

@Suite("Recording lifecycle service")
struct RecordingLifecycleServiceTests {
    @Test("start persists active recording before recorder starts")
    func startPersistsActiveRecordingBeforeRecorderStarts() async throws {
        let store = InMemoryRecordingHistoryStore()
        let recorder = SpyCaptureRecorder {
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
        let recorder = SpyCaptureRecorder(startError: StubCaptureRecorderError.startFailed)
        let service = makeService(store: store, recorder: recorder)

        await #expect(throws: StubCaptureRecorderError.startFailed) {
            try await service.startRecording(try makeRequest())
        }
        #expect(store.activeRecording == nil)
    }

    @Test("stop moves active recording into history after recorder stops")
    func stopMovesActiveRecordingIntoHistoryAfterRecorderStops() async throws {
        let store = InMemoryRecordingHistoryStore()
        let fileURL = URL(fileURLWithPath: "/tmp/luxel.mp4")
        let fileSystem = StubFileSystem(existingFiles: [fileURL])
        let recorder = SpyCaptureRecorder()
        let history = makeHistory(store: store, fileSystem: fileSystem)
        let service = RecordingLifecycleService(recorder: recorder, history: history)
        history.setCurrentRecording(fileURL: fileURL, name: "Active", options: RecordingOptions(frameRate: 30))

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
        let recorder = SpyCaptureRecorder(stopError: StubCaptureRecorderError.stopFailed)
        let history = makeHistory(store: store)
        let service = RecordingLifecycleService(recorder: recorder, history: history)
        history.setCurrentRecording(
            fileURL: URL(fileURLWithPath: "/tmp/luxel.mp4"),
            name: "Active",
            options: RecordingOptions(frameRate: 30)
        )

        await #expect(throws: StubCaptureRecorderError.stopFailed) {
            try await service.stopRecording()
        }
        #expect(store.activeRecording?.name == "Active")
        #expect(store.recordings.isEmpty)
    }

    @Test("pause forwards to recorder while preserving active recording")
    func pauseForwardsToRecorderWhilePreservingActiveRecording() async throws {
        let store = InMemoryRecordingHistoryStore()
        let recorder = SpyCaptureRecorder()
        let history = makeHistory(store: store)
        let service = RecordingLifecycleService(recorder: recorder, history: history)
        let activeRecording = history.setCurrentRecording(
            fileURL: URL(fileURLWithPath: "/tmp/luxel.mp4"),
            name: "Active",
            options: RecordingOptions(frameRate: 30)
        )

        try await service.pauseRecording()

        #expect(store.activeRecording == activeRecording)
        #expect(store.recordings.isEmpty)
        #expect(recorder.pauseCount == 1)
        #expect(recorder.resumeCount == 0)
    }

    @Test("pause rejects missing active recording")
    func pauseRejectsMissingActiveRecording() async throws {
        let store = InMemoryRecordingHistoryStore()
        let recorder = SpyCaptureRecorder()
        let service = makeService(store: store, recorder: recorder)

        await #expect(throws: RecordingLifecycleError.noActiveRecording) {
            try await service.pauseRecording()
        }
        #expect(recorder.pauseCount == 0)
    }

    @Test("pause keeps active recording when recorder fails")
    func pauseKeepsActiveRecordingWhenRecorderFails() async throws {
        let store = InMemoryRecordingHistoryStore()
        let recorder = SpyCaptureRecorder(pauseError: StubCaptureRecorderError.pauseFailed)
        let history = makeHistory(store: store)
        let service = RecordingLifecycleService(recorder: recorder, history: history)
        let activeRecording = history.setCurrentRecording(
            fileURL: URL(fileURLWithPath: "/tmp/luxel.mp4"),
            name: "Active",
            options: RecordingOptions(frameRate: 30)
        )

        await #expect(throws: StubCaptureRecorderError.pauseFailed) {
            try await service.pauseRecording()
        }
        #expect(store.activeRecording == activeRecording)
        #expect(store.recordings.isEmpty)
    }

    @Test("resume forwards to recorder while preserving active recording")
    func resumeForwardsToRecorderWhilePreservingActiveRecording() async throws {
        let store = InMemoryRecordingHistoryStore()
        let recorder = SpyCaptureRecorder()
        let history = makeHistory(store: store)
        let service = RecordingLifecycleService(recorder: recorder, history: history)
        let activeRecording = history.setCurrentRecording(
            fileURL: URL(fileURLWithPath: "/tmp/luxel.mp4"),
            name: "Active",
            options: RecordingOptions(frameRate: 30)
        )

        try await service.resumeRecording()

        #expect(store.activeRecording == activeRecording)
        #expect(store.recordings.isEmpty)
        #expect(recorder.pauseCount == 0)
        #expect(recorder.resumeCount == 1)
    }

    @Test("resume rejects missing active recording")
    func resumeRejectsMissingActiveRecording() async throws {
        let store = InMemoryRecordingHistoryStore()
        let recorder = SpyCaptureRecorder()
        let service = makeService(store: store, recorder: recorder)

        await #expect(throws: RecordingLifecycleError.noActiveRecording) {
            try await service.resumeRecording()
        }
        #expect(recorder.resumeCount == 0)
    }

    @Test("resume keeps active recording when recorder fails")
    func resumeKeepsActiveRecordingWhenRecorderFails() async throws {
        let store = InMemoryRecordingHistoryStore()
        let recorder = SpyCaptureRecorder(resumeError: StubCaptureRecorderError.resumeFailed)
        let history = makeHistory(store: store)
        let service = RecordingLifecycleService(recorder: recorder, history: history)
        let activeRecording = history.setCurrentRecording(
            fileURL: URL(fileURLWithPath: "/tmp/luxel.mp4"),
            name: "Active",
            options: RecordingOptions(frameRate: 30)
        )

        await #expect(throws: StubCaptureRecorderError.resumeFailed) {
            try await service.resumeRecording()
        }
        #expect(store.activeRecording == activeRecording)
        #expect(store.recordings.isEmpty)
    }

    private func makeService(
        store: InMemoryRecordingHistoryStore,
        recorder: SpyCaptureRecorder
    ) -> RecordingLifecycleService {
        RecordingLifecycleService(
            recorder: recorder,
            history: makeHistory(store: store)
        )
    }

    private func makeHistory(
        store: InMemoryRecordingHistoryStore,
        fileSystem: StubFileSystem = StubFileSystem(existingFiles: [URL(fileURLWithPath: "/tmp/luxel.mp4")])
    ) -> RecordingHistoryService {
        RecordingHistoryService(
            store: store,
            fileSystem: fileSystem,
            dateProvider: FixedDateProvider(date: Date(timeIntervalSince1970: 1_595_348_846)),
            mediaProbe: StaticMediaProbe(result: .playable),
            calendar: Calendar(identifier: .gregorian)
        )
    }

    private func makeRequest() throws -> RecordingRequest {
        try RecordingRequest(
            target: .display(DisplayID(9)),
            outputFileURL: URL(fileURLWithPath: "/tmp/luxel.mp4"),
            pixelSize: PixelSize(width: 640, height: 480),
            frameRate: FrameRate(30)
        )
    }
}

private final class SpyCaptureRecorder: CaptureRecorder, @unchecked Sendable {
    private let onStart: @Sendable () -> Void
    private let startError: (any Error)?
    private let pauseError: (any Error)?
    private let resumeError: (any Error)?
    private let stopError: (any Error)?
    private(set) var startCount = 0
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    private(set) var stopCount = 0

    init(
        startError: (any Error)? = nil,
        pauseError: (any Error)? = nil,
        resumeError: (any Error)? = nil,
        stopError: (any Error)? = nil,
        onStart: @escaping @Sendable () -> Void = {}
    ) {
        self.onStart = onStart
        self.startError = startError
        self.pauseError = pauseError
        self.resumeError = resumeError
        self.stopError = stopError
    }

    func startRecording(_ request: RecordingRequest) async throws {
        startCount += 1
        onStart()

        if let startError {
            throw startError
        }
    }

    func pauseRecording() async throws {
        pauseCount += 1

        if let pauseError {
            throw pauseError
        }
    }

    func resumeRecording() async throws {
        resumeCount += 1

        if let resumeError {
            throw resumeError
        }
    }

    func stopRecording() async throws {
        stopCount += 1

        if let stopError {
            throw stopError
        }
    }
}

private enum StubCaptureRecorderError: Error, Equatable {
    case startFailed
    case pauseFailed
    case resumeFailed
    case stopFailed
}

private struct FixedDateProvider: DateProvider {
    let date: Date

    func now() -> Date {
        date
    }
}

private final class StubFileSystem: FileSystem, @unchecked Sendable {
    private let existingFiles: Set<URL>

    init(existingFiles: Set<URL>) {
        self.existingFiles = existingFiles
    }

    func fileExists(at url: URL) -> Bool {
        existingFiles.contains(url)
    }

    func removeFile(at url: URL) throws {}
}
