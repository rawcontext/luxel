import Foundation

public struct StaticMediaProbe: MediaProbe {
    private let result: MediaProbeResult

    public init(result: MediaProbeResult = .playable) {
        self.result = result
    }

    public func inspectRecording(at url: URL) async -> MediaProbeResult {
        result
    }
}
