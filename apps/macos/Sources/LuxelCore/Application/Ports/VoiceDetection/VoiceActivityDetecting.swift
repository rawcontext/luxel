public protocol VoiceActivityDetecting: Sendable {
    func start(deviceID: String?) async -> AsyncStream<VoiceActivityDetectorEvent>
    func stop() async
}
