public protocol AudioInputDeviceUpdateSource: Sendable {
    func inputDeviceUpdates() -> AsyncStream<Void>
}

public struct EmptyAudioInputDeviceUpdateSource: AudioInputDeviceUpdateSource {
    public init() {}

    public func inputDeviceUpdates() -> AsyncStream<Void> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
