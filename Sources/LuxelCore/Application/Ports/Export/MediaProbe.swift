import Foundation

public protocol MediaProbe: Sendable {
    func inspectRecording(at url: URL) async -> MediaProbeResult
}
