import Foundation

public final class AudioLevelBroadcaster: AudioLevelMonitor, @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<AudioLevelSample>.Continuation] = [:]

    public init() {}

    public func start(deviceID: String?) -> AsyncStream<AudioLevelSample> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let id = UUID()
            lock.withLock {
                continuations[id] = continuation
            }
            continuation.yield(.silent)
            continuation.onTermination = { [weak self] _ in
                self?.removeContinuation(id)
            }
        }
    }

    public func stop() {
        let activeContinuations = lock.withLock {
            let activeContinuations = Array(continuations.values)
            continuations.removeAll()
            return activeContinuations
        }

        for continuation in activeContinuations {
            continuation.finish()
        }
    }

    public func publish(_ sample: AudioLevelSample) {
        let activeContinuations = lock.withLock {
            Array(continuations.values)
        }

        for continuation in activeContinuations {
            continuation.yield(sample)
        }
    }

    private func removeContinuation(_ id: UUID) {
        lock.withLock {
            continuations[id] = nil
        }
    }
}
