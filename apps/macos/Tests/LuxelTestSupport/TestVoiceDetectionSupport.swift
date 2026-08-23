import Foundation
import LuxelCore

public actor TestVoiceActivityDetectorSpy: VoiceActivityDetecting {
    public enum Event: Equatable, Sendable {
        case start(String?)
        case stop
    }

    public typealias StartHandler = @Sendable (String?) async -> Void
    public typealias StopHandler = @Sendable () async -> Void

    public private(set) var events: [Event] = []
    private let didStart: StartHandler?
    private let didStop: StopHandler?
    private var continuation: AsyncStream<VoiceActivityDetectorEvent>.Continuation?

    public init(
        didStart: StartHandler? = nil,
        didStop: StopHandler? = nil
    ) {
        self.didStart = didStart
        self.didStop = didStop
    }

    public func start(deviceID: String?) async -> AsyncStream<VoiceActivityDetectorEvent> {
        events.append(.start(deviceID))
        await didStart?(deviceID)
        let stream = AsyncStream.makeStream(of: VoiceActivityDetectorEvent.self)
        continuation = stream.continuation
        return stream.stream
    }

    public func stop() async {
        events.append(.stop)
        await didStop?()
        continuation?.finish()
        continuation = nil
    }
}

public func testSustainedSpeechEvents(
    startingAt startTime: TimeInterval = 0
) -> [VoiceActivityDetectorEvent] {
    (0..<4).map { index in
        .observation(
            VoiceActivityObservation(
                probability: 0.95,
                observedAt: Date(timeIntervalSince1970: startTime + Double(index) * 0.25)
            )
        )
    }
}

@discardableResult
public func createTestVoiceDetectionModelDirectory(at root: URL) throws -> URL {
    let directory = root
        .appending(path: "Models/voice-activity-detection")
        .appending(path: BundledVoiceActivityModelLocator.modelDirectoryName)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}
