import Foundation
import LuxelCore
import LuxelTestSupport
import Testing

@Suite("Replay buffer clip service")
struct ReplayBufferClipServiceTests {
    @Test("clip materializes replay buffer output and records it in history")
    func clipMaterializesReplayBufferOutputAndRecordsItInHistory() async throws {
        let clipURL = URL(fileURLWithPath: "/tmp/replay-15.mp4")
        let store = InMemoryRecordingHistoryStore()
        let context = try makeClipContext(clipURL: clipURL, store: store)

        try await context.replayBufferService.arm(configuration: context.configuration)
        let recording = try await context.service.clip(lastSeconds: 15)

        let expected = PastRecording(
            fileURL: clipURL,
            name: "Luxel Replay 1970-01-01 at 00.16.40",
            date: Date(timeIntervalSince1970: 1_000)
        )
        #expect(recording == expected)
        #expect(store.recordings == [expected])
        #expect(context.engine.clippedDurations() == [15])
    }

    @Test("clip uses configured buffer length when duration is omitted")
    func clipUsesConfiguredBufferLengthWhenDurationIsOmitted() async throws {
        let clipURL = URL(fileURLWithPath: "/tmp/replay-default.mp4")
        let context = try makeClipContext(clipURL: clipURL, bufferLength: 45)

        try await context.replayBufferService.arm(configuration: context.configuration)
        _ = try await context.service.clip()

        #expect(context.engine.clippedDurations() == [45])
    }

    @Test("clip reports missing materialized file")
    func clipReportsMissingMaterializedFile() async throws {
        let clipURL = URL(fileURLWithPath: "/tmp/missing-replay.mp4")
        let context = try makeClipContext(clipURL: clipURL, outputExists: false)

        try await context.replayBufferService.arm(configuration: context.configuration)

        await #expect(throws: ReplayBufferClipServiceError.missingClipFile(clipURL)) {
            _ = try await context.service.clip(lastSeconds: 15)
        }
    }
}

private struct ReplayClipContext {
    let engine: StubReplayBufferEngine
    let replayBufferService: ReplayBufferService
    let service: ReplayBufferClipService
    let configuration: ReplayBufferConfiguration
}

private func makeClipContext(
    clipURL: URL,
    store: InMemoryRecordingHistoryStore = InMemoryRecordingHistoryStore(),
    bufferLength: TimeInterval = 60,
    outputExists: Bool = true
) throws -> ReplayClipContext {
    let engine = StubReplayBufferEngine(clipURL: clipURL)
    let replayBufferService = ReplayBufferService(engine: engine)
    let existingFiles = outputExists ? Set([clipURL]) : []
    let history = RecordingHistoryService(
        store: store,
        fileSystem: ExistingReplayFileSystem(existingFiles: existingFiles),
        dateProvider: FixedReplayClipDateProvider(now: Date(timeIntervalSince1970: 1_000)),
        mediaProbe: StaticMediaProbe(result: .playable),
        calendar: utcCalendar()
    )
    return try ReplayClipContext(
        engine: engine,
        replayBufferService: replayBufferService,
        service: ReplayBufferClipService(
            replayBufferService: replayBufferService,
            history: history
        ),
        configuration: ReplayBufferConfiguration(
            bufferLength: bufferLength,
            source: .displayWithCursor,
            frameRate: FrameRate(30)
        )
    )
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

private typealias ExistingReplayFileSystem = ExistingTestFileSystem
