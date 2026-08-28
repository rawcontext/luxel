import Foundation
import LuxelCore
import LuxelTestSupport
import Testing

@Suite("Recording lifecycle service")
struct RecordingLifecycleServiceTests {
}

extension RecordingLifecycleServiceTests {
    func makeService(
        store: InMemoryRecordingHistoryStore,
        recorder: RecordingLifecycleRecorderSpy,
        dateProvider: any DateProvider = RecordingLifecycleFixedDateProvider(
            date: Date(timeIntervalSince1970: 1_595_348_846)),
        autoStopScheduler: any RecordingAutoStopScheduler = RecordingLifecycleAutoStopScheduler(),
        countdownSleeper: any RecordingCountdownSleeper = RecordingLifecycleCountdownSleeperSpy(),
        userNotifier: (any UserNotifier)? = nil,
        replayBufferService: ReplayBufferService? = nil
    ) -> RecordingLifecycleService {
        RecordingLifecycleService(
            recorder: recorder,
            history: makeHistory(store: store, dateProvider: dateProvider),
            dateProvider: dateProvider,
            autoStopScheduler: autoStopScheduler,
            countdownSleeper: countdownSleeper,
            userNotifier: userNotifier,
            replayBufferService: replayBufferService
        )
    }

    func makeHistory(
        store: InMemoryRecordingHistoryStore,
        fileSystem: any FileSystem = RecordingLifecycleStubFileSystem(existingFiles: [
            URL(fileURLWithPath: "/tmp/luxel.mp4")
        ]),
        dateProvider: any DateProvider = RecordingLifecycleFixedDateProvider(
            date: Date(timeIntervalSince1970: 1_595_348_846))
    ) -> RecordingHistoryService {
        RecordingHistoryService(
            store: store,
            fileSystem: fileSystem,
            dateProvider: dateProvider,
            mediaProbe: StaticMediaProbe(result: .playable),
            calendar: Calendar(identifier: .gregorian)
        )
    }

    func makeRequest(
        outputFileURL: URL = URL(fileURLWithPath: "/tmp/luxel.mp4"),
        schedule: RecordingSchedule? = nil
    ) throws -> RecordingRequest {
        try RecordingRequest(
            target: .display(DisplayID(9)),
            outputFileURL: outputFileURL,
            pixelSize: PixelSize(width: 640, height: 480),
            frameRate: FrameRate(30),
            schedule: schedule
        )
    }
}

final class RecordingLifecycleRecorderSpy: CaptureRecorder, @unchecked Sendable {
    private let onStart: @Sendable () -> Void
    private let startError: (any Error)?
    private let pauseError: (any Error)?
    private let resumeError: (any Error)?
    private let stopError: (any Error)?
    private(set) var startCount = 0
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    private(set) var stopCount = 0
    private(set) var startedRequests: [RecordingRequest] = []

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
        startedRequests.append(request)
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

enum RecordingLifecycleRecorderError: Error, Equatable {
    case startFailed
    case pauseFailed
    case resumeFailed
    case stopFailed
}

typealias RecordingLifecycleReplayCommand = TestReplayBufferCommand
typealias RecordingLifecycleReplayEngineSpy = TestReplayBufferEngine

final class RecordingLifecycleCountdownSleeperSpy: RecordingCountdownSleeper, @unchecked Sendable {
    private let error: (any Error)?
    private let onSleep: @Sendable () -> Void
    private let lock = NSLock()
    private(set) var sleepDurations: [TimeInterval] = []

    init(
        error: (any Error)? = nil,
        onSleep: @escaping @Sendable () -> Void = {}
    ) {
        self.error = error
        self.onSleep = onSleep
    }

    func sleep(for duration: TimeInterval) async throws {
        lock.withLock {
            sleepDurations.append(duration)
        }
        onSleep()

        if let error {
            throw error
        }
    }
}

enum RecordingLifecycleOutputError: Error, Equatable {
    case moveFailed
    case missingSource
}

struct RecordingLifecycleOutputMove: Equatable {
    let sourceURL: URL
    let destinationURL: URL
}

final class RecordingLifecycleOutputFileSystem: FileSystem, @unchecked Sendable {
    private var existingFiles: Set<URL>
    private let moveError: (any Error)?
    private(set) var movedFiles: [RecordingLifecycleOutputMove] = []
    private(set) var removedFiles: [URL] = []

    init(existingFiles: Set<URL>, moveError: (any Error)? = nil) {
        self.existingFiles = existingFiles
        self.moveError = moveError
    }

    func fileExists(at url: URL) -> Bool {
        existingFiles.contains(url)
    }

    func createDirectory(at url: URL) throws {}

    func copyFile(from sourceURL: URL, to destinationURL: URL) throws {}

    func moveFile(from sourceURL: URL, to destinationURL: URL) throws {
        if let moveError {
            throw moveError
        }

        guard existingFiles.contains(sourceURL) else {
            throw RecordingLifecycleOutputError.missingSource
        }

        existingFiles.remove(sourceURL)
        existingFiles.insert(destinationURL)
        movedFiles.append(
            RecordingLifecycleOutputMove(
                sourceURL: sourceURL,
                destinationURL: destinationURL
            ))
    }

    func writeData(_ data: Data, to url: URL) throws {}

    func removeFile(at url: URL) throws {
        existingFiles.remove(url)
        removedFiles.append(url)
    }

    func trashItem(at url: URL) throws {}
}

struct RecordingLifecycleFixedDateProvider: DateProvider {
    let date: Date

    func now() -> Date {
        date
    }
}

final class RecordingLifecycleMutableDateProvider: DateProvider, @unchecked Sendable {
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

final class RecordingLifecycleAutoStopScheduler: RecordingAutoStopScheduler, @unchecked Sendable {
    private let lock = NSLock()
    private var scheduledTasks: [RecordingLifecycleAutoStopScheduledTask] = []

    var scheduledIntervals: [TimeInterval] {
        lock.withLock {
            scheduledTasks.map(\.interval)
        }
    }

    func schedule(
        after interval: TimeInterval,
        operation: @escaping @Sendable () async -> Void
    ) -> any RecordingAutoStopTask {
        let task = RecordingLifecycleAutoStopTask()
        let scheduledTask = RecordingLifecycleAutoStopScheduledTask(
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

struct RecordingLifecycleAutoStopScheduledTask: Sendable {
    let interval: TimeInterval
    let task: RecordingLifecycleAutoStopTask
    let operation: @Sendable () async -> Void
}

final class RecordingLifecycleAutoStopTask: RecordingAutoStopTask, @unchecked Sendable {
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

actor RecordingLifecycleUserNotifierSpy: UserNotifier {
    private var recordingDurations: [TimeInterval] = []

    func notifyExportCompleted(fileURL: URL, presetName: String) async throws {}

    func notifyRecordingAutoStopped(duration: TimeInterval) async throws {
        recordingDurations.append(duration)
    }

    func recordingAutoStoppedDurations() -> [TimeInterval] {
        recordingDurations
    }
}

typealias RecordingLifecycleStubFileSystem = ExistingTestFileSystem
