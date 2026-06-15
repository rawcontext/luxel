import Foundation

public protocol CaptureRecorder: Sendable {
    func startRecording(_ request: RecordingRequest) async throws
    func pauseRecording() async throws
    func resumeRecording() async throws
    func stopRecording() async throws
}
