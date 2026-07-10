import AppKit
import Foundation
import LuxelCore

@MainActor
extension LuxelMenuModel {
    func refreshNotchDisplays() {
        notchDisplays = notchDisplayProvider.displays()
    }

    func watchNotchDisplayUpdates() async {
        for await displays in notchDisplayProvider.displayUpdates {
            notchDisplays = displays
            await refreshNotchSurface()
        }
    }

    var notchSurfaceStatusPresentation: NotchSurfaceStatusPresentation {
        NotchSurfaceStatusPresentation(
            displays: notchDisplays,
            preferences: settings.notchSurfacePreferences
        )
    }

    func refreshNotchSurface(
        reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    ) async {
        let now = Date()

        await notchCoordinator.present(
            activities: [notchActivity(now: now)],
            displays: notchDisplays,
            preferences: settings.notchSurfacePreferences,
            presentationState: notchPresentationState,
            recordingActionToReplace: activeNotchRecordingActionID,
            reduceMotion: reduceMotion
        )
    }

    func watchNotchInteractions(
        openEditor: @escaping @MainActor (URL) -> Void,
        openSettings: @escaping @MainActor () -> Void,
        showAreaCapturePicker: @escaping @MainActor () -> Void
    ) async {
        for await interaction in notchCoordinator.interactions {
            await handleNotchInteraction(
                interaction,
                openEditor: openEditor,
                openSettings: openSettings,
                showAreaCapturePicker: showAreaCapturePicker
            )
        }
    }

    private func handleNotchInteraction(
        _ interaction: NotchInteraction,
        openEditor: @escaping @MainActor (URL) -> Void,
        openSettings: @escaping @MainActor () -> Void,
        showAreaCapturePicker: @escaping @MainActor () -> Void
    ) async {
        switch interaction {
        case .hoverEntered:
            notchPresentationState = .expanded
            await refreshNotchSurface()
        case .hoverExited:
            notchPresentationState = .collapsed
            await refreshNotchSurface()
        case .setExpanded(let isExpanded):
            notchPresentationState = isExpanded ? .expanded : .collapsed
            await refreshNotchSurface()
        case .action(let actionID):
            await performNotchAction(
                actionID,
                openEditor: openEditor,
                openSettings: openSettings,
                showAreaCapturePicker: showAreaCapturePicker
            )
        case .dragArtifact:
            break
        }
    }

    private func performNotchAction(
        _ actionID: NotchActivityActionID,
        openEditor: @escaping @MainActor (URL) -> Void,
        openSettings: @escaping @MainActor () -> Void,
        showAreaCapturePicker: @escaping @MainActor () -> Void
    ) async {
        let handledCaptureAction = await performNotchCaptureAction(
            actionID,
            showAreaCapturePicker: showAreaCapturePicker
        )
        if !handledCaptureAction {
            await performNotchUtilityAction(
                actionID,
                openEditor: openEditor,
                openSettings: openSettings
            )
        }
        await refreshNotchSurface()
    }

    private func performNotchCaptureAction(
        _ actionID: NotchActivityActionID,
        showAreaCapturePicker: @escaping @MainActor () -> Void
    ) async -> Bool {
        switch actionID {
        case .recordAudioOnly:
            guard canUseAudioOnlyButton else {
                if let source = notchAudioCaptureRecoverySource() {
                    presentPermissionPrompt(forSource: source)
                }
                return true
            }
            await startAudioOnlyRecording(notchRecordingActionID: .recordAudioOnly)
            return true
        case .recordArea, .recordWindow, .recordFullscreen, .retry:
            await performScreenDependentNotchAction(
                actionID,
                showAreaCapturePicker: showAreaCapturePicker
            )
            return true
        default:
            return false
        }
    }

    private func performScreenDependentNotchAction(
        _ actionID: NotchActivityActionID,
        showAreaCapturePicker: @escaping @MainActor () -> Void
    ) async {
        guard canUseScreenDependentNotchAction else {
            presentPermissionPrompt(forSource: .screenPixels)
            return
        }
        switch actionID {
        case .recordArea:
            showAreaCapturePicker()
        case .recordWindow:
            await startActiveWindowRecording(notchRecordingActionID: .recordWindow)
        case .recordFullscreen:
            await refreshCaptureTargets()
            await startFullscreenRecording(notchRecordingActionID: .recordFullscreen)
        case .retry:
            await refreshCaptureTargets()
            await startRecordingFromSelectedTarget()
        default:
            break
        }
    }

    private func performNotchUtilityAction(
        _ actionID: NotchActivityActionID,
        openEditor: @escaping @MainActor (URL) -> Void,
        openSettings: @escaping @MainActor () -> Void
    ) async {
        switch actionID {
        case .openSettings:
            openSettings()
        case .cancel:
            _ = await stopRecording()
        case .pauseRecording, .resumeRecording:
            await pauseOrResumeRecording()
        case .stopRecording:
            openRecordingIfNeeded(await stopRecording(), openEditor: openEditor)
        case .discardRecording:
            await discardActiveRecording()
        case .cancelExport:
            cancelQuickExport()
        case .recordArea, .recordWindow, .recordFullscreen, .recordAudioOnly, .retry,
             .toggleMute, .quickGIF, .markMoment, .clipReplay, .pauseReplayBuffer,
             .cancelProcessing, .revealStorage, .reveal, .copy, .openInEditor,
             .openInPreview, .save:
            break
        }
    }

    private func openRecordingIfNeeded(
        _ stopAction: RecordingStopAction?,
        openEditor: @escaping @MainActor (URL) -> Void
    ) {
        if case .openEditor(let fileURL) = stopAction {
            openEditor(fileURL)
        }
    }

    private func notchActivity(now: Date) -> NotchActivity {
        guard notchPresentationState == .expanded else {
            return .dormant
        }

        switch recordingState {
        case .idle:
            return .idleHover
        case .starting, .stopping:
            return .processing
        case .countingDown(let startedAt, let duration):
            return .arming(remaining: max(0, duration - now.timeIntervalSince(startedAt)))
        case .recording(let recording, let clock),
             .pausing(let recording, let clock),
             .resuming(let recording, let clock):
            return .recording(
                elapsed: clock.elapsed(at: now),
                audioLevel: audioLevelSample,
                muted: !recording.options.audio.capturesAudio
            )
        case .paused(_, let clock):
            return .paused(elapsed: clock.elapsed(at: now))
        case .exporting(let snapshot):
            return .exporting(snapshot: snapshot)
        case .failed(let message):
            let recoveryAction: NotchRecoveryAction? =
                message.localizedCaseInsensitiveContains("permission")
                ? .openSettings
                : .retry
            return
                (try? NotchError(
                    title: "Recording Failed",
                    message: message,
                    recoveryAction: recoveryAction
                )).map(NotchActivity.error) ?? .dormant
        }
    }

    private var canUseScreenDependentNotchAction: Bool {
        screenRecordingStatus == .authorized
    }

    private func notchAudioCaptureRecoverySource() -> CapturePermissionSource? {
        let microphone = sourcePermissionPresentation(for: .microphone)
        let systemAudio = sourcePermissionPresentation(for: .systemAudio)

        if microphone.needsSetup {
            return .microphone
        }

        if systemAudio.needsSetup {
            return .systemAudio
        }

        if microphone.phase == .offByUser {
            return .microphone
        }

        if systemAudio.phase == .offByUser {
            return .systemAudio
        }

        return nil
    }

}
