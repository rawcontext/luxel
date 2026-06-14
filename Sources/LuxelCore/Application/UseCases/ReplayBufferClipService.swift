import Foundation

public final class ReplayBufferClipService: Sendable {
    private let replayBufferService: ReplayBufferService
    private let history: RecordingHistoryService

    public init(
        replayBufferService: ReplayBufferService,
        history: RecordingHistoryService
    ) {
        self.replayBufferService = replayBufferService
        self.history = history
    }

    public func clip(lastSeconds: TimeInterval? = nil) async throws -> PastRecording {
        let fileURL = try await replayBufferService.clip(lastSeconds: lastSeconds)
        guard let recording = history.addReplayClip(fileURL: fileURL) else {
            throw ReplayBufferClipServiceError.missingClipFile(fileURL)
        }

        return recording
    }
}

public enum ReplayBufferClipServiceError: Error, Equatable {
    case missingClipFile(URL)
}
