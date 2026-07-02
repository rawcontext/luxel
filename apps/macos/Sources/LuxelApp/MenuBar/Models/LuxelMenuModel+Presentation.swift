import Foundation
import LuxelCore
import SwiftUI

@MainActor
extension LuxelMenuModel {
    var hasActiveRecording: Bool {
        switch recordingState {
        case .countingDown, .recording, .pausing, .paused, .resuming, .stopping:
            return true
        case .idle, .starting, .exporting, .failed:
            return false
        }
    }

    var hasActiveAudioOnlyRecording: Bool {
        isRecordingAudioOnly
    }

    var canUseRecordButton: Bool {
        recordingPresentation().canUsePrimaryAction
    }

    var audioLevelMonitorTaskID: String {
        [
            settings.recordAudio.description,
            String(describing: microphoneStatus),
            settings.audioInputDeviceID ?? AudioInputDeviceID.systemDefault
        ].joined(separator: ":")
    }

    var recordingAudioLevelMonitorTaskID: String {
        "\(audioLevelMonitorTaskID):\(hasActiveRecording)"
    }

    var shouldShowRecordingAudioLevelMeter: Bool {
        recordingState.activeRecording?.options.audio.capturesAudio == true
    }

    var canPauseOrResumeRecording: Bool {
        !isRecordingAudioOnly && recordingPresentation().secondaryActionTitle != nil
    }

    var canUsePauseResumeButton: Bool {
        !isRecordingAudioOnly && recordingPresentation().canUseSecondaryAction
    }

    var canUseAudioOnlyButton: Bool {
        switch recordingState {
        case .idle, .failed:
            captureCapabilities.audioOnlyRecordingAvailable
        case .starting, .countingDown, .recording, .pausing, .paused, .resuming, .stopping, .exporting:
            false
        }
    }

    var canUseRecordAgainButton: Bool {
        switch recordingState {
        case .idle, .failed:
            captureCapabilities.recordAgainAvailable
        case .starting, .countingDown, .recording, .pausing, .paused, .resuming, .stopping, .exporting:
            false
        }
    }

    var canUseQuickRecordLastButton: Bool {
        canUseRecordAgainButton && settings.quickExportPresetID != nil
    }

    var canSelectArea: Bool {
        switch recordingState {
        case .idle, .failed:
            captureCapabilities.areaRecordingAvailable
        case .starting, .countingDown, .recording, .pausing, .paused, .resuming, .stopping, .exporting:
            false
        }
    }

    var selectedCaptureTarget: CaptureTargetOption? {
        guard let selectedCaptureTargetID else {
            return nil
        }

        return captureTargets.first { $0.id == selectedCaptureTargetID }
    }

    var lastCaptureFallbackDisplay: CaptureTargetOption? {
        captureTargets.first { $0.kind == .display }
    }

    var selectedOrFallbackDisplayTarget: CaptureTargetOption? {
        if selectedCaptureTarget?.kind == .display {
            return selectedCaptureTarget
        }

        return lastCaptureFallbackDisplay
    }

    var fullscreenCaptureTarget: CaptureTargetOption? {
        fullscreenCaptureTargetResolver.resolve(
            from: captureTargets,
            pointerDisplayID: pointerDisplayProvider.displayIDContainingPointer(),
            selectedTargetID: selectedCaptureTargetID
        )
    }

    var canStartRecording: Bool {
        captureCapabilities.screenRecordingAvailable
    }

    var isRecordingAudioOnly: Bool {
        recordingState.activeRecording?.options.isAudioOnly == true
    }

    func recordingPresentation(now: Date = Date()) -> RecordingSessionPresentation {
        RecordingSessionPresentation(
            state: recordingState.presentationState(now: now),
            canStartRecording: canStartRecording,
            showElapsedTimeInMenuBar: settings.showTimeInMenuBar
        )
    }

    func menuBarStatusPresentation(now: Date = Date()) -> RecordingSessionPresentation {
        let state =
            switch recordingState {
            case .countingDown, .recording, .pausing, .paused, .resuming, .stopping:
                recordingState.presentationState(now: now)
            case .idle, .starting, .exporting, .failed:
                RecordingSessionPresentationState.idle
            }

        return RecordingSessionPresentation(
            state: state,
            canStartRecording: canStartRecording,
            showElapsedTimeInMenuBar: settings.showTimeInMenuBar
        )
    }

    func cropperQuickRecordingConfiguration() -> CropperQuickRecordingConfiguration {
        CropperQuickRecordingConfiguration(
            activePresetID: settings.quickExportPresetID,
            presets: settings.exportPresets
        )
    }

    func cropperSelectionPresetConfiguration() -> CropperSelectionPresetConfiguration {
        CropperSelectionPresetConfiguration(sizePresets: settings.userSizePresets)
    }

    func cropperRestoreSelectionConfiguration() -> CropperRestoreSelectionConfiguration {
        CropperRestoreSelectionConfiguration(
            isEnabled: settings.restoreLastSelection,
            memory: settings.lastCaptureMemory
        )
    }

    var replayBufferMenuPresentation: ReplayBufferMenuPresentation {
        ReplayBufferMenuPresentation(
            configuration: settings.replayBufferConfiguration,
            state: replayBufferState
        )
    }

    var recordButtonTitle: String {
        recordingPresentation().primaryActionTitle
    }

    var recordButtonSystemImage: String {
        recordingPresentation().primaryActionSystemImage
    }

    var pauseResumeButtonTitle: String {
        recordingPresentation().secondaryActionTitle ?? "Pause"
    }

    var pauseResumeButtonSystemImage: String {
        recordingPresentation().secondaryActionSystemImage ?? "pause.circle"
    }

    var recordingStatusMessage: String? {
        switch recordingState {
        case .idle:
            nil
        case .starting:
            "Starting recording"
        case .countingDown:
            recordingPresentation().statusMessage
        case .recording(let recording, _):
            recording.name
        case .pausing(let recording, _):
            "Pausing \(recording.name)"
        case .paused(let recording, _):
            "Paused \(recording.name)"
        case .resuming(let recording, _):
            "Resuming \(recording.name)"
        case .stopping:
            "Finishing recording"
        case .exporting(let snapshot):
            snapshot.actionTitle
        case .failed(let message):
            message
        }
    }

    var recordingStatusTint: Color {
        if case .failed = recordingState {
            return .red
        }

        return .secondary
    }

    var recoveryStatusMessage: String? {
        switch recoveryState {
        case .none:
            nil
        case .recovered(let recording):
            "Recovered \(recording.name)"
        case .knownCorrupt(let fileURL, _):
            "Recovered repairable corrupt recording \(fileURL.lastPathComponent)"
        case .unknownCorrupt(let fileURL, _):
            "Recorded diagnostic for corrupt recording \(fileURL.lastPathComponent)"
        }
    }

    var recoveryStatusTint: Color {
        switch recoveryState {
        case .knownCorrupt, .unknownCorrupt:
            .orange
        case .none, .recovered:
            .secondary
        }
    }

    var recordingsDirectorySummary: String {
        let name = settings.recordingsDirectory.lastPathComponent
        return name.isEmpty ? settings.recordingsDirectory.path : name
    }
}
