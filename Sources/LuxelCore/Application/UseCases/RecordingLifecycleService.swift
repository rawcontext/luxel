import Foundation

public final class RecordingLifecycleService: Sendable {
    private let recorder: any CaptureRecorder
    private let history: RecordingHistoryService

    public init(recorder: any CaptureRecorder, history: RecordingHistoryService) {
        self.recorder = recorder
        self.history = history
    }

    @discardableResult
    public func startRecording(
        _ request: RecordingRequest,
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

    public func pauseRecording() async throws {
        guard history.getCurrentRecording() != nil else {
            throw RecordingLifecycleError.noActiveRecording
        }

        try await recorder.pauseRecording()
    }

    public func resumeRecording() async throws {
        guard history.getCurrentRecording() != nil else {
            throw RecordingLifecycleError.noActiveRecording
        }

        try await recorder.resumeRecording()
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

public enum RecordingLifecycleError: Error, Equatable {
    case noActiveRecording
}
