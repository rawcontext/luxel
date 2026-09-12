import Foundation
import LuxelCore

@MainActor
extension LuxelMenuModel {
    func refreshRecentRecordings() {
        recentRecordings = recordingHistoryService.getPastRecordings()

        if recentRecordingFilter != .all,
            !recentRecordings.contains(where: recentRecordingFilter.includes) {
            recentRecordingFilter = .all
        }
    }

    var filteredRecentRecordings: [PastRecording] {
        Array(recentRecordings.filter(recentRecordingFilter.includes).prefix(5))
    }

    var canFilterRecentRecordings: Bool {
        false
    }

    func refreshCaptureTargets() async {
        guard screenRecordingStatus == .authorized else {
            captureTargets = []
            selectedCaptureTargetID = nil
            captureTargetStatusMessage = nil
            syncCameraPreviewSnapArea()
            return
        }

        do {
            try await captureTargetService.refresh()
            captureTargets = try await captureTargetService.availableTargets()
            if selectedCaptureTarget == nil {
                selectedCaptureTargetID = captureTargets.first?.id
            }
            captureTargetStatusMessage =
                captureTargets.isEmpty ? LuxelLocalization.string("No capture targets found") : nil
            syncCameraPreviewSnapArea()
        } catch {
            captureTargets = []
            selectedCaptureTargetID = nil
            captureTargetStatusMessage = errorMessage(error)
            syncCameraPreviewSnapArea()
        }
    }

    func recoverInterruptedRecording() async -> PastRecording? {
        guard !hasActiveRecording else {
            return nil
        }

        switch await recordingHistoryService.recoverActiveRecording() {
        case .none:
            return nil
        case .playable(let recording):
            recoveryState = .recovered(recording)
            refreshRecentRecordings()
            return recording
        case .knownCorrupt(let fileURL, let reason):
            recoveryState = .knownCorrupt(fileURL: fileURL, reason: reason)
            recoveryPrompt = RecoveryPrompt(fileURL: fileURL, reason: reason, isKnownRepairable: true)
            refreshRecentRecordings()
            return nil
        case .unknownCorrupt(let fileURL, let reason):
            recoveryState = .unknownCorrupt(fileURL: fileURL, reason: reason)
            recoveryPrompt = RecoveryPrompt(fileURL: fileURL, reason: reason, isKnownRepairable: false)
            refreshRecentRecordings()
            return nil
        }
    }

    func revealRecoveredRecording(_ prompt: RecoveryPrompt) {
        withRecordingsDirectoryAccess { _ in
            fileWorkflowService.revealInFinder(prompt.fileURL)
        }
        recoveryPrompt = nil
    }

    func copyRecoveryError(_ prompt: RecoveryPrompt) {
        fileWorkflowService.copyText(prompt.reason)
        recoveryPrompt = nil
    }

    func revealRecording(_ recording: PastRecording) {
        withRecordingsDirectoryAccess { _ in
            fileWorkflowService.revealInFinder(recording.fileURL)
        }
    }

    func removeKeystrokeData(from recording: PastRecording) {
        do {
            try recordingHistoryService.removeKeystrokeData(from: recording)
            refreshRecentRecordings()
        } catch {
            recordingActionErrorMessage = errorMessage(error)
        }
    }

    func transcriptSourceContext(for mediaURL: URL) -> TranscriptSourceContext {
        let standardizedURL = mediaURL.standardizedFileURL
        let recordings = recentRecordings + recordingHistoryService.getPastRecordings()
        guard
            let recording = recordings.first(where: { recording in
                recording.fileURL.standardizedFileURL == standardizedURL
                    || recording.primaryMediaURL.standardizedFileURL == standardizedURL
            })
        else {
            return .unknown
        }

        return TranscriptSourceContext(recordingAudioMode: recording.options.audio)
    }

    private func withRecordingsDirectoryAccess(_ operation: (URL) -> Void) {
        guard let bookmark = settings.recordingsDirectoryBookmark else {
            operation(settings.recordingsDirectory)
            return
        }

        let result = directoryAccessService.withAccess(to: bookmark) { directory in
            operation(directory.url)
            return true
        }

        if result.value == nil {
            recordingActionErrorMessage = errorMessage(
                MenuDirectoryAccessError.revoked(result.directory.url))
        }
    }
}

private enum MenuDirectoryAccessError: LocalizedError {
    case revoked(URL)

    var errorDescription: String? {
        switch self {
        case .revoked(let url):
            LuxelLocalization.format(
                "Luxel no longer has permission to open %@. Choose the recordings folder again.", url.lastPathComponent)
        }
    }
}
