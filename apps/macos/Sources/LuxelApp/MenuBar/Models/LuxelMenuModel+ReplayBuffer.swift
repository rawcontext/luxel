import Foundation
import LuxelCore

@MainActor
extension LuxelMenuModel {
    func watchReplayBufferState() async {
        guard let replayBufferService else {
            return
        }

        for await state in replayBufferService.replayBufferState {
            replayBufferState = state
        }
    }

    func reconcileReplayBufferOnLaunch() async {
        guard settings.replayBufferResumeOnLaunch,
            settings.replayBufferConfiguration != nil
        else {
            return
        }

        await reconcileReplayBufferSettings()
    }

    func setReplayBufferEnabled(_ isEnabled: Bool) {
        if isEnabled {
            guard
                let configuration = replayBufferConfiguration(
                    bufferLength: settings.replayBufferPreferredBufferLength
                )
            else {
                return
            }

            settings.replayBufferPreferredBufferLength = configuration.bufferLength
            settings.replayBufferConfiguration = configuration
            saveSettings()
            requestReplayBufferArm(configuration)
        } else {
            settings.replayBufferConfiguration = nil
            settings.replayBufferResumeOnLaunch = false
            saveSettings()
            Task {
                await disarmReplayBuffer()
            }
        }
    }

    func setReplayBufferResumeOnLaunch(_ isEnabled: Bool) {
        settings.replayBufferResumeOnLaunch = isEnabled

        guard isEnabled,
            settings.replayBufferConfiguration == nil,
            let configuration = replayBufferConfiguration(
                bufferLength: settings.replayBufferPreferredBufferLength
            )
        else {
            saveSettings()
            return
        }

        settings.replayBufferPreferredBufferLength = configuration.bufferLength
        settings.replayBufferConfiguration = configuration
        saveSettings()
        requestReplayBufferArm(configuration)
    }

    func setReplayBufferDuration(_ bufferLength: TimeInterval) {
        guard let updatedConfiguration = replayBufferConfiguration(bufferLength: bufferLength)
        else {
            return
        }

        settings.replayBufferPreferredBufferLength = updatedConfiguration.bufferLength
        if settings.replayBufferConfiguration != nil {
            settings.replayBufferConfiguration = updatedConfiguration
        }
        saveSettings()
        if settings.replayBufferConfiguration != nil {
            Task {
                await reconcileReplayBufferSettings()
            }
        }
    }

    func reconcileReplayBufferSettings() async {
        guard let configuration = settings.replayBufferConfiguration else {
            await disarmReplayBuffer()
            return
        }

        requestReplayBufferArm(configuration)
    }

    func approveReplayBufferConsent() async {
        guard let prompt = replayBufferConsentPrompt else {
            return
        }

        replayBufferConsentPrompt = nil
        settings.replayBufferConsentAccepted = true
        settings.replayBufferConfiguration = prompt.configuration
        saveSettings()
        await armReplayBuffer(prompt.configuration)
    }

    func denyReplayBufferConsent() {
        replayBufferConsentPrompt = nil
        settings.replayBufferConfiguration = nil
        saveSettings()
    }

    func toggleReplayBufferPause() async {
        guard let replayBufferService else {
            return
        }

        do {
            switch replayBufferState {
            case .paused(.user):
                try await replayBufferService.resumeByUser()
            case .paused:
                break
            case .buffering:
                try await replayBufferService.pauseByUser()
            case .starting, .disarmed, .clipping:
                break
            }
        } catch {
            recordingActionErrorMessage = errorMessage(error)
        }
    }

    func clipReplayBufferFromMenu(openRecording: @escaping @MainActor (URL) -> Void) async {
        guard replayBufferMenuPresentation.canClip else {
            return
        }

        do {
            _ = try await clipAutomationReplayBuffer(seconds: nil, openRecording: openRecording)
            recordingActionErrorMessage = nil
        } catch {
            recordingActionErrorMessage = errorMessage(error)
        }
    }

    func stopReplayBufferFromMenu(openRecording: @escaping @MainActor (URL) -> Void) async {
        if replayBufferMenuPresentation.canClip {
            do {
                _ = try await clipAutomationReplayBuffer(seconds: nil, openRecording: openRecording)
                recordingActionErrorMessage = nil
            } catch {
                recordingActionErrorMessage = errorMessage(error)
            }
        }

        settings.replayBufferConfiguration = nil
        saveSettings()
        await disarmReplayBuffer()
    }

    private func requestReplayBufferArm(_ configuration: ReplayBufferConfiguration) {
        guard settings.replayBufferConsentAccepted else {
            replayBufferConsentPrompt = ReplayBufferConsentPrompt(configuration: configuration)
            return
        }

        Task {
            await armReplayBuffer(configuration)
        }
    }

    private func armReplayBuffer(_ configuration: ReplayBufferConfiguration) async {
        guard let replayBufferService else {
            return
        }

        await refreshPermissions()
        guard screenRecordingStatus == .authorized else {
            presentPermissionPrompt(forSource: .screenPixels)
            return
        }

        do {
            try await replayBufferService.arm(configuration: configuration)
            recordingActionErrorMessage = nil
        } catch {
            recordingActionErrorMessage = errorMessage(error)
        }
    }

    private func disarmReplayBuffer() async {
        guard let replayBufferService else {
            return
        }

        do {
            try await replayBufferService.disarm()
            replayBufferState = .disarmed
        } catch {
            recordingActionErrorMessage = errorMessage(error)
        }
    }

    private func replayBufferConfiguration(
        bufferLength: TimeInterval
    ) -> ReplayBufferConfiguration? {
        let base = settings.replayBufferConfiguration ?? ReplayBufferConfiguration.defaults
        return try? ReplayBufferConfiguration(
            bufferLength: bufferLength,
            source: base.source,
            frameRate: base.frameRate,
            includeSystemAudio: base.includeSystemAudio,
            quality: base.quality
        )
    }
}
