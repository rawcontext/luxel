import Foundation

public final class AudioRecordingLifecycleService: Sendable {
    private let recorder: any AudioRecorder
    private let history: RecordingHistoryService

    public init(recorder: any AudioRecorder, history: RecordingHistoryService) {
        self.recorder = recorder
        self.history = history
    }

    @discardableResult
    public func startRecording(
        _ request: AudioRecordingRequest,
        name: String? = nil
    ) async throws -> ActiveRecording {
        let activeRecording = history.setCurrentRecording(
            fileURL: request.outputFileURL,
            name: name,
            options: request.recordingOptions
        )

        do {
            try await recorder.startRecording(request)
            return activeRecording
        } catch {
            history.clearCurrentRecording()
            throw error
        }
    }

    @discardableResult
    public func stopRecording(recordingName: String? = nil) async throws -> PastRecording {
        try await recorder.stopRecording()

        guard let recording = history.stopCurrentRecording(recordingName: recordingName) else {
            throw RecordingLifecycleError.noActiveRecording
        }

        return recording
    }
}
