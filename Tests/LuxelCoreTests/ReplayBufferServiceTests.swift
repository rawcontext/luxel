import Foundation
import LuxelCore
import Testing

@Suite("Replay buffer service")
struct ReplayBufferServiceTests {
    @Test("arm and disarm delegate to the engine")
    func armAndDisarmDelegateToEngine() async throws {
        let engine = SpyReplayBufferEngine()
        let service = ReplayBufferService(engine: engine)
        let configuration = try replayConfiguration(length: 60)

        try await service.arm(configuration: configuration)
        try await service.disarm()

        #expect(engine.commands() == [
            .arm(configuration),
            .disarm
        ])
    }

    @Test("recording activity pauses and resumes when buffer was active")
    func recordingActivityPausesAndResumesWhenBufferWasActive() async throws {
        let engine = SpyReplayBufferEngine()
        let service = ReplayBufferService(engine: engine)
        let configuration = try replayConfiguration(length: 60)

        try await service.arm(configuration: configuration)
        try await service.recordingDidStart()
        try await service.recordingDidStop()

        #expect(engine.commands() == [
            .arm(configuration),
            .pause(.recordingActive),
            .resume
        ])
    }

    @Test("user pause survives recording activity")
    func userPauseSurvivesRecordingActivity() async throws {
        let engine = SpyReplayBufferEngine()
        let service = ReplayBufferService(engine: engine)
        let configuration = try replayConfiguration(length: 60)

        try await service.arm(configuration: configuration)
        try await service.pauseByUser()
        try await service.recordingDidStart()
        try await service.recordingDidStop()
        try await service.resumeByUser()

        #expect(engine.commands() == [
            .arm(configuration),
            .pause(.user),
            .resume
        ])
    }

    @Test("recording pause temporarily overrides lower priority system pause")
    func recordingPauseTemporarilyOverridesLowerPrioritySystemPause() async throws {
        let engine = SpyReplayBufferEngine()
        let service = ReplayBufferService(engine: engine)
        let configuration = try replayConfiguration(length: 60)

        try await service.arm(configuration: configuration)
        try await service.pauseForSystemReason(.battery)
        try await service.recordingDidStart()
        try await service.recordingDidStop()
        try await service.resumeSystemReason(.battery)

        #expect(engine.commands() == [
            .arm(configuration),
            .pause(.battery),
            .pause(.recordingActive),
            .pause(.battery),
            .resume
        ])
    }

    @Test("clip delegates requested and default durations")
    func clipDelegatesRequestedAndDefaultDurations() async throws {
        let engine = SpyReplayBufferEngine()
        let service = ReplayBufferService(engine: engine)
        let configuration = try replayConfiguration(length: 60)

        try await service.arm(configuration: configuration)
        let defaultClip = try await service.clip()
        let requestedClip = try await service.clip(lastSeconds: 15)

        #expect(defaultClip == URL(fileURLWithPath: "/tmp/replay-60.mp4"))
        #expect(requestedClip == URL(fileURLWithPath: "/tmp/replay-15.mp4"))
        #expect(engine.commands() == [
            .arm(configuration),
            .clip(60),
            .clip(15)
        ])
    }

    @Test("service rejects unarmed and invalid clip requests")
    func serviceRejectsUnarmedAndInvalidClipRequests() async throws {
        let engine = SpyReplayBufferEngine()
        let service = ReplayBufferService(engine: engine)

        await #expect(throws: ReplayBufferServiceError.notArmed) {
            _ = try await service.clip()
        }

        try await service.arm(configuration: replayConfiguration(length: 60))
        await #expect(throws: ReplayBufferModelError.invalidClipDuration) {
            _ = try await service.clip(lastSeconds: 0)
        }
    }

    @Test("recording and system activity are ignored while disarmed")
    func recordingAndSystemActivityAreIgnoredWhileDisarmed() async throws {
        let engine = SpyReplayBufferEngine()
        let service = ReplayBufferService(engine: engine)

        try await service.recordingDidStart()
        try await service.recordingDidStop()
        try await service.pauseForSystemReason(.locked)
        try await service.resumeSystemReason(.locked)

        #expect(engine.commands().isEmpty)
    }

    @Test("arming applies current system pause reasons")
    func armingAppliesCurrentSystemPauseReasons() async throws {
        let engine = SpyReplayBufferEngine()
        let monitor = StubSystemActivityMonitor(
            currentPauseReasons: [.battery],
            stream: AsyncStream { $0.finish() }
        )
        let service = ReplayBufferService(engine: engine, systemActivityMonitor: monitor)
        let configuration = try replayConfiguration(length: 60)

        try await service.arm(configuration: configuration)

        #expect(engine.commands() == [
            .arm(configuration),
            .pause(.battery)
        ])
    }

    @Test("system activity stream pauses resumes and restarts display changes")
    func systemActivityStreamPausesResumesAndRestartsDisplayChanges() async throws {
        let engine = SpyReplayBufferEngine()
        let events = AsyncStream<SystemActivityEvent>.makeStream()
        let monitor = StubSystemActivityMonitor(currentPauseReasons: [], stream: events.stream)
        let service = ReplayBufferService(engine: engine, systemActivityMonitor: monitor)
        let configuration = try replayConfiguration(length: 60)

        try await service.arm(configuration: configuration)
        events.continuation.yield(.pauseReasonBecameActive(.locked))
        events.continuation.yield(.pauseReasonBecameInactive(.locked))
        events.continuation.yield(.displayConfigurationChanged)

        let commands = await engine.waitForCommands(count: 5)
        #expect(commands == [
            .arm(configuration),
            .pause(.locked),
            .resume,
            .pause(.displayChanged),
            .resume
        ])
    }

    private func replayConfiguration(length: TimeInterval) throws -> ReplayBufferConfiguration {
        try ReplayBufferConfiguration(
            bufferLength: length,
            source: .displayWithCursor,
            frameRate: FrameRate(30)
        )
    }
}

private struct StubSystemActivityMonitor: SystemActivityMonitor {
    let currentPauseReasons: Set<ReplayBufferPauseReason>
    let stream: AsyncStream<SystemActivityEvent>

    func events() -> AsyncStream<SystemActivityEvent> {
        stream
    }
}

private enum SpyReplayBufferCommand: Equatable {
    case arm(ReplayBufferConfiguration)
    case pause(ReplayBufferPauseReason)
    case resume
    case disarm
    case clip(TimeInterval)
}

private final class SpyReplayBufferEngine: ReplayBufferEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedCommands: [SpyReplayBufferCommand] = []

    var state: AsyncStream<ReplayBufferState> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func arm(configuration: ReplayBufferConfiguration) async throws {
        append(.arm(configuration))
    }

    func pause(reason: ReplayBufferPauseReason) async throws {
        append(.pause(reason))
    }

    func resume() async throws {
        append(.resume)
    }

    func disarm() async throws {
        append(.disarm)
    }

    func clip(lastSeconds: TimeInterval) async throws -> URL {
        append(.clip(lastSeconds))
        return URL(fileURLWithPath: "/tmp/replay-\(Int(lastSeconds)).mp4")
    }

    func commands() -> [SpyReplayBufferCommand] {
        lock.withLock {
            recordedCommands
        }
    }

    func waitForCommands(count: Int) async -> [SpyReplayBufferCommand] {
        for _ in 0..<50 {
            let commands = commands()
            if commands.count >= count {
                return commands
            }

            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        return commands()
    }

    private func append(_ command: SpyReplayBufferCommand) {
        lock.withLock {
            recordedCommands.append(command)
        }
    }
}
