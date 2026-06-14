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
        recentRecordings.contains { $0.kind == .recording }
            && recentRecordings.contains { $0.kind == .screenshot }
    }

    func refreshCaptureTargets() async {
        guard screenRecordingStatus == .authorized else {
            captureTargets = []
            selectedCaptureTargetID = nil
            captureTargetStatusMessage = nil
            return
        }

        do {
            captureTargets = try await captureTargetService.availableTargets()
            if selectedCaptureTarget == nil {
                selectedCaptureTargetID = captureTargets.first?.id
            }
            captureTargetStatusMessage = captureTargets.isEmpty ? "No capture targets found" : nil
        } catch {
            captureTargets = []
            selectedCaptureTargetID = nil
            captureTargetStatusMessage = errorMessage(error)
        }
    }

    func keepCaptureTargetCacheWarm() async {
        await refreshCaptureTargetCacheIfAuthorized()

        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            await refreshCaptureTargetCacheIfAuthorized()
        }
    }

    private func refreshCaptureTargetCacheIfAuthorized() async {
        guard await permissionClient.status(for: .screenRecording) == .authorized else {
            return
        }

        try? await captureTargetService.refresh()
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
        fileWorkflowService.revealInFinder(prompt.fileURL)
        recoveryPrompt = nil
    }

    func copyRecoveryError(_ prompt: RecoveryPrompt) {
        fileWorkflowService.copyText(prompt.reason)
        recoveryPrompt = nil
    }

    func revealRecording(_ recording: PastRecording) {
        fileWorkflowService.revealInFinder(recording.fileURL)
    }
}
