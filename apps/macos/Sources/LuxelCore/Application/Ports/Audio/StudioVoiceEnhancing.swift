import Foundation

public struct StudioVoiceWindow: Equatable, Sendable {
    public let streamID: UUID
    public let samples: [Float]
    public let sampleRate: Int
    public let beginsStream: Bool
    public let endsStream: Bool

    public init(
        streamID: UUID,
        samples: [Float],
        sampleRate: Int,
        beginsStream: Bool,
        endsStream: Bool
    ) {
        self.streamID = streamID
        self.samples = samples
        self.sampleRate = sampleRate
        self.beginsStream = beginsStream
        self.endsStream = endsStream
    }
}

public typealias StudioVoiceProgressHandler = @Sendable (Double) async -> Void

public protocol StudioVoiceEnhancing: Sendable {
    func enhance(
        _ input: StudioVoiceWindow,
        progress: StudioVoiceProgressHandler?
    ) async throws -> StudioVoiceWindow
}
