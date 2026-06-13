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

    @Test("start schedules auto stop when request has max recorded duration")
    func startSchedulesAutoStop() async throws {
        let store = InMemoryRecordingHistoryStore()
        let dateProvider = MutableDateProvider(Date(timeIntervalSince1970: 1_000))
        let scheduler = ManualAutoStopScheduler()
        let service = makeService(
            store: store,
            recorder: SpyCaptureRecorder(),
            dateProvider: dateProvider,
            autoStopScheduler: scheduler
        )
        let request = try makeRequest(schedule: RecordingSchedule(maxRecordedDuration: 60))

        _ = try await service.startRecording(request)

        #expect(scheduler.scheduledIntervals == [60])
    }

    @Test("auto stop uses normal stop path")
    func autoStopUsesNormalStopPath() async throws {
        let store = InMemoryRecordingHistoryStore()
        let dateProvider = MutableDateProvider(Date(timeIntervalSince1970: 1_000))
        let scheduler = ManualAutoStopScheduler()
        let recorder = SpyCaptureRecorder()
        let service = makeService(
            store: store,
            recorder: recorder,
            dateProvider: dateProvider,
            autoStopScheduler: scheduler
        )
        let request = try makeRequest(schedule: RecordingSchedule(maxRecordedDuration: 60))

        let activeRecording = try await service.startRecording(request, name: "Timed")
        await scheduler.fireScheduledTask(at: 0)

        #expect(recorder.stopCount == 1)
        #expect(store.activeRecording == nil)
        #expect(store.recordings == [activeRecording.pastRecording])
    }

    @Test("auto stop notifies recording completion")
    func autoStopNotifiesRecordingCompletion() async throws {
        let store = InMemoryRecordingHistoryStore()
        let dateProvider = MutableDateProvider(Date(timeIntervalSince1970: 1_000))
        let scheduler = ManualAutoStopScheduler()
        let notifier = SpyUserNotifier()
        let service = makeService(
            store: store,
            recorder: SpyCaptureRecorder(),
            dateProvider: dateProvider,
            autoStopScheduler: scheduler,
            userNotifier: notifier
        )
        let request = try makeRequest(schedule: RecordingSchedule(maxRecordedDuration: 60))

        _ = try await service.startRecording(request)
        await scheduler.fireScheduledTask(at: 0)

        #expect(await notifier.recordingAutoStoppedDurations() == [60])
    }

    @Test("auto stop publishes stopped recording")
    func autoStopPublishesStoppedRecording() async throws {
        let store = InMemoryRecordingHistoryStore()
        let dateProvider = MutableDateProvider(Date(timeIntervalSince1970: 1_000))
        let scheduler = ManualAutoStopScheduler()
        let service = makeService(
            store: store,
            recorder: SpyCaptureRecorder(),
            dateProvider: dateProvider,
            autoStopScheduler: scheduler
        )
        let request = try makeRequest(schedule: RecordingSchedule(maxRecordedDuration: 60))
        let stream = service.autoStoppedRecordings
        let eventTask = Task<PastRecording?, Never> {
            var iterator = stream.makeAsyncIterator()
            return await iterator.next()
        }

        let activeRecording = try await service.startRecording(request)
        await scheduler.fireScheduledTask(at: 0)

        #expect(await eventTask.value == activeRecording.pastRecording)
    }

    @Test("pause suspends auto stop and resume schedules remaining recorded time")
    func pauseSuspendsAutoStopAndResumeSchedulesRemainingRecordedTime() async throws {
        let store = InMemoryRecordingHistoryStore()
        let dateProvider = MutableDateProvider(Date(timeIntervalSince1970: 1_000))
        let scheduler = ManualAutoStopScheduler()
        let service = makeService(
            store: store,
            recorder: SpyCaptureRecorder(),
            dateProvider: dateProvider,
            autoStopScheduler: scheduler
        )
        let request = try makeRequest(schedule: RecordingSchedule(maxRecordedDuration: 60))

        _ = try await service.startRecording(request)
        dateProvider.setDate(Date(timeIntervalSince1970: 1_010))
        try await service.pauseRecording()
        dateProvider.setDate(Date(timeIntervalSince1970: 1_040))
        try await service.resumeRecording()

        #expect(scheduler.scheduledIntervals == [60, 50])
        #expect(scheduler.isCanceled(at: 0))
        #expect(!scheduler.isCanceled(at: 1))
    }

    @Test("manual stop cancels pending auto stop")
    func manualStopCancelsPendingAutoStop() async throws {
        let store = InMemoryRecordingHistoryStore()
        let dateProvider = MutableDateProvider(Date(timeIntervalSince1970: 1_000))
        let scheduler = ManualAutoStopScheduler()
        let recorder = SpyCaptureRecorder()
        let service = makeService(
            store: store,
            recorder: recorder,
            dateProvider: dateProvider,
            autoStopScheduler: scheduler
        )
        let request = try makeRequest(schedule: RecordingSchedule(maxRecordedDuration: 60))

        _ = try await service.startRecording(request)
        _ = try await service.stopRecording()
        await scheduler.fireScheduledTask(at: 0)

        #expect(recorder.stopCount == 1)
        #expect(scheduler.isCanceled(at: 0))
    }

    @Test("manual stop does not notify recording auto stop")
    func manualStopDoesNotNotifyRecordingAutoStop() async throws {
        let store = InMemoryRecordingHistoryStore()
        let dateProvider = MutableDateProvider(Date(timeIntervalSince1970: 1_000))
        let scheduler = ManualAutoStopScheduler()
        let notifier = SpyUserNotifier()
        let service = makeService(
            store: store,
            recorder: SpyCaptureRecorder(),
            dateProvider: dateProvider,
            autoStopScheduler: scheduler,
            userNotifier: notifier
        )
        let request = try makeRequest(schedule: RecordingSchedule(maxRecordedDuration: 60))

        _ = try await service.startRecording(request)
        _ = try await service.stopRecording()

        #expect(await notifier.recordingAutoStoppedDurations().isEmpty)
    }

    private func makeService(
        store: InMemoryRecordingHistoryStore,
        recorder: SpyCaptureRecorder,
        dateProvider: any DateProvider = FixedDateProvider(date: Date(timeIntervalSince1970: 1_595_348_846)),
        autoStopScheduler: any RecordingAutoStopScheduler = ManualAutoStopScheduler(),
        userNotifier: (any UserNotifier)? = nil
    ) -> RecordingLifecycleService {
        RecordingLifecycleService(
            recorder: recorder,
            history: makeHistory(store: store, dateProvider: dateProvider),
            dateProvider: dateProvider,
            autoStopScheduler: autoStopScheduler,
            userNotifier: userNotifier
        )
    }

    private func makeHistory(
        store: InMemoryRecordingHistoryStore,
        fileSystem: StubFileSystem = StubFileSystem(existingFiles: [URL(fileURLWithPath: "/tmp/luxel.mp4")]),
        dateProvider: any DateProvider = FixedDateProvider(date: Date(timeIntervalSince1970: 1_595_348_846))
    ) -> RecordingHistoryService {
        RecordingHistoryService(
            store: store,
            fileSystem: fileSystem,
            dateProvider: dateProvider,
            mediaProbe: StaticMediaProbe(result: .playable),
            calendar: Calendar(identifier: .gregorian)
        )
    }

    private func makeRequest(schedule: RecordingSchedule? = nil) throws -> RecordingRequest {
        try RecordingRequest(
            target: .display(DisplayID(9)),
            outputFileURL: URL(fileURLWithPath: "/tmp/luxel.mp4"),
            pixelSize: PixelSize(width: 640, height: 480),
            frameRate: FrameRate(30),
            schedule: schedule
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

private final class MutableDateProvider: DateProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) {
        self.date = date
    }

    func now() -> Date {
        lock.withLock {
            date
        }
    }

    func setDate(_ date: Date) {
        lock.withLock {
            self.date = date
        }
    }
}

private final class ManualAutoStopScheduler: RecordingAutoStopScheduler, @unchecked Sendable {
    private let lock = NSLock()
    private var scheduledTasks: [ManualAutoStopScheduledTask] = []

    var scheduledIntervals: [TimeInterval] {
        lock.withLock {
            scheduledTasks.map(\.interval)
        }
    }

    func schedule(
        after interval: TimeInterval,
        operation: @escaping @Sendable () async -> Void
    ) -> any RecordingAutoStopTask {
        let task = ManualAutoStopTask()
        let scheduledTask = ManualAutoStopScheduledTask(
            interval: interval,
            task: task,
            operation: operation
        )

        lock.withLock {
            scheduledTasks.append(scheduledTask)
        }

        return task
    }

    func isCanceled(at index: Int) -> Bool {
        lock.withLock {
            guard scheduledTasks.indices.contains(index) else {
                return false
            }

            return scheduledTasks[index].task.isCanceled
        }
    }

    func fireScheduledTask(at index: Int) async {
        let scheduledTask = lock.withLock {
            scheduledTasks.indices.contains(index) ? scheduledTasks[index] : nil
        }

        guard let scheduledTask, !scheduledTask.task.isCanceled else {
            return
        }

        await scheduledTask.operation()
    }
}

private struct ManualAutoStopScheduledTask: Sendable {
    let interval: TimeInterval
    let task: ManualAutoStopTask
    let operation: @Sendable () async -> Void
}

private final class ManualAutoStopTask: RecordingAutoStopTask, @unchecked Sendable {
    private let lock = NSLock()
    private var canceled = false

    var isCanceled: Bool {
        lock.withLock {
            canceled
        }
    }

    func cancel() {
        lock.withLock {
            canceled = true
        }
    }
}

private actor SpyUserNotifier: UserNotifier {
    private var recordingDurations: [TimeInterval] = []

    func notifyExportCompleted(fileURL: URL, presetName: String) async throws {}

    func notifyRecordingAutoStopped(duration: TimeInterval) async throws {
        recordingDurations.append(duration)
    }

    func recordingAutoStoppedDurations() -> [TimeInterval] {
        recordingDurations
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

    func createDirectory(at url: URL) throws {}

    func copyFile(from sourceURL: URL, to destinationURL: URL) throws {}

    func removeFile(at url: URL) throws {}

    func trashItem(at url: URL) throws {}
}
