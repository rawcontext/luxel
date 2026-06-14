import Foundation

public protocol ReplayBufferEngine: Sendable {
    var state: AsyncStream<ReplayBufferState> { get }

    func arm(configuration: ReplayBufferConfiguration) async throws
    func pause(reason: ReplayBufferPauseReason) async throws
    func resume() async throws
    func disarm() async throws
    func clip(lastSeconds: TimeInterval) async throws -> URL
}
