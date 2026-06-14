import Foundation
import LuxelCore
import SwiftUI

@MainActor
extension LuxelMenuModel {
    var hasActiveRecording: Bool {
        switch recordingState {
        case .recording, .pausing, .paused, .resuming, .stopping:
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
        recordingState.activeRecording?.options.audio.capturesMicrophone == true
            && microphoneStatus == .authorized
    }

    var canPauseOrResumeRecording: Bool {
        !isRecordingAudioOnly && recordingPresentation().secondaryActionTitle != nil
    }

    var canUsePauseResumeButton: Bool {
        !isRecordingAudioOnly && recordingPresentation().canUseSecondaryAction
    }

    var canUseQuickRecordButton: Bool {
        switch recordingState {
        case .idle, .failed:
            canStartRecording && settings.quickExportPresetID != nil
        case .starting, .recording, .pausing, .paused, .resuming, .stopping, .exporting:
            false
        }
    }

    var canUseAudioOnlyButton: Bool {
        switch recordingState {
        case .idle, .failed:
            microphoneStatus == .authorized
        case .starting, .recording, .pausing, .paused, .resuming, .stopping, .exporting:
            false
        }
    }

    var canUseRecordAgainButton: Bool {
        switch recordingState {
        case .idle, .failed:
            screenRecordingStatus == .authorized && settings.lastCaptureMemory != nil
        case .starting, .recording, .pausing, .paused, .resuming, .stopping, .exporting:
            false
        }
    }

    var canUseQuickRecordLastButton: Bool {
        canUseRecordAgainButton && settings.quickExportPresetID != nil
    }

    var canCaptureScreenshot: Bool {
        switch recordingState {
        case .idle, .failed:
            screenRecordingStatus == .authorized && selectedCaptureTarget != nil
        case .starting, .recording, .pausing, .paused, .resuming, .stopping, .exporting:
            false
        }
    }

    var canSelectArea: Bool {
        switch recordingState {
        case .idle, .failed:
            screenRecordingStatus == .authorized
        case .starting, .recording, .pausing, .paused, .resuming, .stopping, .exporting:
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

    var canStartRecording: Bool {
        screenRecordingStatus == .authorized && selectedCaptureTarget != nil
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
