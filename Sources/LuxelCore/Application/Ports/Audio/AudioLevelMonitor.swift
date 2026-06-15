public protocol AudioLevelMonitor: Sendable {
    func start(deviceID: String?) -> AsyncStream<AudioLevelSample>
    func stop()
}

public struct SilentAudioLevelMonitor: AudioLevelMonitor {
    public init() {}

    public func start(deviceID: String?) -> AsyncStream<AudioLevelSample> {
        AsyncStream { continuation in
            continuation.yield(.silent)
            continuation.finish()
        }
    }

    public func stop() {}
}
