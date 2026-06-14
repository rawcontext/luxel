import Foundation
import LuxelCore
import Testing

@Suite("Replay buffer clip service")
struct ReplayBufferClipServiceTests {
    @Test("clip materializes replay buffer output and records it in history")
    func clipMaterializesReplayBufferOutputAndRecordsItInHistory() async throws {
        let clipURL = URL(fileURLWithPath: "/tmp/replay-15.mp4")
        let engine = StubReplayBufferEngine(clipURL: clipURL)
        let replayBufferService = ReplayBufferService(engine: engine)
        let store = InMemoryRecordingHistoryStore()
        let history = RecordingHistoryService(
            store: store,
            fileSystem: ExistingReplayFileSystem(existingFiles: [clipURL]),
            dateProvider: FixedReplayClipDateProvider(now: Date(timeIntervalSince1970: 1_000)),
            mediaProbe: StaticMediaProbe(result: .playable),
            calendar: utcCalendar()
        )
        let service = ReplayBufferClipService(
            replayBufferService: replayBufferService,
            history: history
        )
        let configuration = try ReplayBufferConfiguration(
            bufferLength: 60,
            source: .displayWithCursor,
            frameRate: FrameRate(30)
        )

        try await replayBufferService.arm(configuration: configuration)
        let recording = try await service.clip(lastSeconds: 15)

        let expected = PastRecording(
            fileURL: clipURL,
            name: "Luxel Replay 1970-01-01 at 00.16.40",
            date: Date(timeIntervalSince1970: 1_000)
        )
        #expect(recording == expected)
        #expect(store.recordings == [expected])
        #expect(engine.clippedDurations() == [15])
    }

    @Test("clip uses configured buffer length when duration is omitted")
    func clipUsesConfiguredBufferLengthWhenDurationIsOmitted() async throws {
        let clipURL = URL(fileURLWithPath: "/tmp/replay-default.mp4")
        let engine = StubReplayBufferEngine(clipURL: clipURL)
        let replayBufferService = ReplayBufferService(engine: engine)
        let history = RecordingHistoryService(
            store: InMemoryRecordingHistoryStore(),
            fileSystem: ExistingReplayFileSystem(existingFiles: [clipURL]),
            dateProvider: FixedReplayClipDateProvider(now: Date(timeIntervalSince1970: 1_000)),
            mediaProbe: StaticMediaProbe(result: .playable),
            calendar: utcCalendar()
        )
        let service = ReplayBufferClipService(
            replayBufferService: replayBufferService,
            history: history
        )
        let configuration = try ReplayBufferConfiguration(
            bufferLength: 45,
            source: .displayWithCursor,
            frameRate: FrameRate(30)
        )

        try await replayBufferService.arm(configuration: configuration)
        _ = try await service.clip()

        #expect(engine.clippedDurations() == [45])
    }

    @Test("clip reports missing materialized file")
    func clipReportsMissingMaterializedFile() async throws {
        let clipURL = URL(fileURLWithPath: "/tmp/missing-replay.mp4")
        let engine = StubReplayBufferEngine(clipURL: clipURL)
        let replayBufferService = ReplayBufferService(engine: engine)
        let history = RecordingHistoryService(
            store: InMemoryRecordingHistoryStore(),
            fileSystem: ExistingReplayFileSystem(),
            dateProvider: FixedReplayClipDateProvider(now: Date(timeIntervalSince1970: 1_000)),
            mediaProbe: StaticMediaProbe(result: .playable),
            calendar: utcCalendar()
        )
        let service = ReplayBufferClipService(
            replayBufferService: replayBufferService,
            history: history
        )
        let configuration = try ReplayBufferConfiguration(
            bufferLength: 60,
            source: .displayWithCursor,
            frameRate: FrameRate(30)
        )

        try await replayBufferService.arm(configuration: configuration)

        await #expect(throws: ReplayBufferClipServiceError.missingClipFile(clipURL)) {
            _ = try await service.clip(lastSeconds: 15)
        }
    }
}

private func utcCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}

private final class StubReplayBufferEngine: ReplayBufferEngine, @unchecked Sendable {
    private let lock = NSLock()
    private let clipURL: URL
    private var durations: [TimeInterval] = []

    init(clipURL: URL) {
        self.clipURL = clipURL
    }

    var state: AsyncStream<ReplayBufferState> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func arm(configuration: ReplayBufferConfiguration) async throws {}

    func pause(reason: ReplayBufferPauseReason) async throws {}

    func resume() async throws {}

    func disarm() async throws {}

    func clip(lastSeconds: TimeInterval) async throws -> URL {
        lock.withLock {
            durations.append(lastSeconds)
        }
        return clipURL
    }

    func clippedDurations() -> [TimeInterval] {
        lock.withLock {
            durations
        }
    }
}

private struct FixedReplayClipDateProvider: DateProvider {
    let nowValue: Date

    init(now: Date) {
        self.nowValue = now
    }

    func now() -> Date {
        nowValue
    }
}

private final class ExistingReplayFileSystem: FileSystem, @unchecked Sendable {
    private let existingFiles: Set<URL>

    init(existingFiles: Set<URL> = []) {
        self.existingFiles = existingFiles
    }

    func fileExists(at url: URL) -> Bool {
        existingFiles.contains(url)
    }

    func createDirectory(at url: URL) throws {}

    func copyFile(from sourceURL: URL, to destinationURL: URL) throws {}

    func writeData(_ data: Data, to url: URL) throws {}

    func removeFile(at url: URL) throws {}

    func trashItem(at url: URL) throws {}
}
