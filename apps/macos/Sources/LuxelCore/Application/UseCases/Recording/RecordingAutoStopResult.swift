import Foundation

public struct RecordingAutoStopResult: Sendable {
    public let fileURL: URL
    public let result: Result<PastRecording, any Error>
}
