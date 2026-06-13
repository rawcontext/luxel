public protocol AudioRecorder: Sendable {
    func startRecording(_ request: AudioRecordingRequest) async throws
    func stopRecording() async throws
}
