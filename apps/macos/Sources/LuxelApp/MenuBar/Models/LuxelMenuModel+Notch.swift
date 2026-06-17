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

    func refreshNotchSurface(reduceMotion: Bool = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) async {
        let now = Date()

        await notchCoordinator.present(
            activities: [notchActivity(now: now)],
            displays: notchDisplays,
            preferences: settings.notchSurfacePreferences,
            presentationState: notchPresentationState,
            reduceMotion: reduceMotion
        )
    }

    func watchNotchInteractions(
        openEditor: @escaping @MainActor (URL) -> Void,
        openSettings: @escaping @MainActor () -> Void,
        showAreaCapturePicker: @escaping @MainActor () -> Void,
        showScreenshotCapturePicker: @escaping @MainActor () -> Void
    ) async {
        for await interaction in notchCoordinator.interactions {
            await handleNotchInteraction(
                interaction,
                openEditor: openEditor,
                openSettings: openSettings,
                showAreaCapturePicker: showAreaCapturePicker,
                showScreenshotCapturePicker: showScreenshotCapturePicker
            )
        }
    }

    private func handleNotchInteraction(
        _ interaction: NotchInteraction,
        openEditor: @escaping @MainActor (URL) -> Void,
        openSettings: @escaping @MainActor () -> Void,
        showAreaCapturePicker: @escaping @MainActor () -> Void,
        showScreenshotCapturePicker: @escaping @MainActor () -> Void
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
                showAreaCapturePicker: showAreaCapturePicker,
                showScreenshotCapturePicker: showScreenshotCapturePicker
            )
        case .dragArtifact:
            break
        }
    }

    private func performNotchAction(
        _ actionID: NotchActivityActionID,
        openEditor: @escaping @MainActor (URL) -> Void,
        openSettings: @escaping @MainActor () -> Void,
        showAreaCapturePicker: @escaping @MainActor () -> Void,
        showScreenshotCapturePicker: @escaping @MainActor () -> Void
    ) async {
        switch actionID {
        case .recordArea:
            showAreaCapturePicker()
        case .recordWindow:
            await startActiveWindowRecording()
        case .recordFullscreen:
            await refreshCaptureTargets()
            await startFullscreenRecording()
        case .screenshot:
            showScreenshotCapturePicker()
        case .openSettings:
            openSettings()
        case .cancel:
            _ = await stopRecording()
        case .pauseRecording, .resumeRecording:
            await pauseOrResumeRecording()
        case .stopRecording:
            let stopAction = await stopRecording()
            openRecordingIfNeeded(stopAction, openEditor: openEditor)
        case .discardRecording:
            await discardActiveRecording()
        case .toggleMute:
            break
        case .cancelExport:
            cancelQuickExport()
        case .retry:
            await refreshCaptureTargets()
            await startRecordingFromSelectedTarget()
        case .quickGIF, .markMoment, .clipReplay, .pauseReplayBuffer, .cancelProcessing, .revealStorage,
             .reveal, .copy, .openInEditor, .openInPreview, .save:
            break
        }

        await refreshNotchSurface()
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
                muted: !recording.options.audio.capturesMicrophone
            )
        case .paused(_, let clock):
            return .paused(elapsed: clock.elapsed(at: now))
        case .exporting(let snapshot):
            return .exporting(snapshot: snapshot)
        case .failed(let message):
            let recoveryAction: NotchRecoveryAction? = message.localizedCaseInsensitiveContains("permission")
                ? .openSettings
                : .retry
            return (try? NotchError(
                title: "Recording Failed",
                message: message,
                recoveryAction: recoveryAction
            )).map(NotchActivity.error) ?? .dormant
        }
    }

}
