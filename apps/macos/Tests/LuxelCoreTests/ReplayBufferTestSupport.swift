import Foundation
import LuxelCore

enum TestReplayBufferCommand: Equatable {
    case arm(ReplayBufferConfiguration)
    case pause(ReplayBufferPauseReason)
    case resume
    case disarm
    case clip(TimeInterval)
}

final class TestReplayBufferEngine: ReplayBufferEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedCommands: [TestReplayBufferCommand] = []

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

    func commands() -> [TestReplayBufferCommand] {
        lock.withLock { recordedCommands }
    }

    func waitForCommands(count: Int) async -> [TestReplayBufferCommand] {
        for _ in 0..<50 {
            let commands = commands()
            if commands.count >= count {
                return commands
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        return commands()
    }

    private func append(_ command: TestReplayBufferCommand) {
        lock.withLock { recordedCommands.append(command) }
    }
}
