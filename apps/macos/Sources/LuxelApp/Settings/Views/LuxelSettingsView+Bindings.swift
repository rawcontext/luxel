import Foundation
import LuxelCore
import LuxelPresentation
import SwiftUI

extension LuxelSettingsView {
    var replayBufferEnabled: Binding<Bool> {
        Binding {
            model.settings.replayBufferConfiguration != nil
        } set: { isEnabled in
            model.setReplayBufferEnabled(isEnabled)
        }
    }

    var replayBufferLengthSelection: Binding<TimeInterval> {
        Binding {
            model.settings.replayBufferConfiguration?.bufferLength
                ?? model.settings.replayBufferPreferredBufferLength
        } set: { bufferLength in
            model.setReplayBufferDuration(bufferLength)
        }
    }

    var replayBufferResumeOnLaunch: Binding<Bool> {
        Binding {
            model.settings.replayBufferResumeOnLaunch
        } set: { isEnabled in
            model.setReplayBufferResumeOnLaunch(isEnabled)
        }
    }

    var replayBufferFrameRateSelection: Binding<Int> {
        Binding {
            model.settings.replayBufferConfiguration?.frameRate.framesPerSecond
                ?? ReplayBufferConfiguration.defaults.frameRate.framesPerSecond
        } set: { frameRate in
            updateReplayBufferConfiguration(frameRate: frameRate)
        }
    }

    var replayBufferSystemAudioSelection: Binding<Bool> {
        Binding {
            model.settings.replayBufferConfiguration?.includeSystemAudio
                ?? ReplayBufferConfiguration.defaults.includeSystemAudio
        } set: { includeSystemAudio in
            updateReplayBufferConfiguration(includeSystemAudio: includeSystemAudio)
        }
    }

    var notchSurfaceEnabled: Binding<Bool> {
        notchSurfaceSettingsBinding(\.isEnabled) { settings, isEnabled in
            try settings.replacing(isEnabled: isEnabled)
        }
    }

    var notchIdleHoverActionsEnabled: Binding<Bool> {
        notchSurfaceSettingsBinding(\.idleHoverActionsEnabled) { settings, isEnabled in
            try settings.replacing(idleHoverActionsEnabled: isEnabled)
        }
    }

    var notchWaveformEnabled: Binding<Bool> {
        notchSurfaceSettingsBinding(\.showsWaveform) { settings, isEnabled in
            try settings.replacing(showsWaveform: isEnabled)
        }
    }

    var notchAutoCollapseSecondsSelection: Binding<TimeInterval> {
        Binding {
            model.settings.notchSurfaceSettings.autoCollapseSeconds
        } set: { seconds in
            updateNotchSurfaceSettings { settings in
                try settings.replacing(autoCollapseSeconds: seconds)
            }
        }
    }

    var notchFloatingHUDFallbackEnabled: Binding<Bool> {
        notchSurfaceSettingsBinding(\.fallbackToFloatingHUDWhenUnavailable) { settings, isEnabled in
            try settings.replacing(fallbackToFloatingHUDWhenUnavailable: isEnabled)
        }
    }

    func notchSurfaceSettingsBinding(
        _ keyPath: KeyPath<NotchSurfaceSettings, Bool>,
        update: @escaping (NotchSurfaceSettings, Bool) throws -> NotchSurfaceSettings
    ) -> Binding<Bool> {
        Binding {
            model.settings.notchSurfaceSettings[keyPath: keyPath]
        } set: { value in
            updateNotchSurfaceSettings { settings in
                try update(settings, value)
            }
        }
    }

    func updateNotchSurfaceSettings(
        _ update: (NotchSurfaceSettings) throws -> NotchSurfaceSettings
    ) {
        guard let settings = try? update(model.settings.notchSurfaceSettings) else {
            return
        }

        model.settings.notchSurfaceSettings = settings
    }

    var audioInputDeviceSelection: Binding<String> {
        Binding {
            model.settings.audioInputDeviceID ?? AudioInputDeviceID.systemDefault
        } set: { deviceID in
            model.settings.audioInputDeviceID = deviceID
            model.settings.audioInputDeviceName =
                model.audioInputDevices
                .first { $0.id == deviceID }?
                .name
        }
    }

    var cameraPreviewShapeSelection: Binding<CameraOverlayShape> {
        Binding {
            model.settings.cameraPreviewStyle.shape
        } set: { shape in
            let style = model.settings.cameraPreviewStyle
            model.settings.cameraPreviewStyle = CameraPreviewStyle(
                shape: shape,
                size: style.size,
                isMirrored: style.isMirrored
            )
        }
    }

    var cameraPreviewSizeSelection: Binding<CameraPreviewSize> {
        Binding {
            model.settings.cameraPreviewStyle.size
        } set: { size in
            let style = model.settings.cameraPreviewStyle
            model.settings.cameraPreviewStyle = CameraPreviewStyle(
                shape: style.shape,
                size: size,
                isMirrored: style.isMirrored
            )
        }
    }

    var cameraPreviewMirroredSelection: Binding<Bool> {
        Binding {
            model.settings.cameraPreviewStyle.isMirrored
        } set: { isMirrored in
            let style = model.settings.cameraPreviewStyle
            model.settings.cameraPreviewStyle = CameraPreviewStyle(
                shape: style.shape,
                size: style.size,
                isMirrored: isMirrored
            )
        }
    }

    func updateReplayBufferConfiguration(
        bufferLength: TimeInterval? = nil,
        frameRate: Int? = nil,
        includeSystemAudio: Bool? = nil
    ) {
        let configuration =
            model.settings.replayBufferConfiguration ?? ReplayBufferConfiguration.defaults
        guard
            let updatedFrameRate = try? FrameRate(frameRate ?? configuration.frameRate.framesPerSecond),
            let updatedConfiguration = try? ReplayBufferConfiguration(
                bufferLength: bufferLength ?? configuration.bufferLength,
                source: configuration.source,
                frameRate: updatedFrameRate,
                includeSystemAudio: includeSystemAudio ?? configuration.includeSystemAudio,
                quality: configuration.quality
            )
        else {
            return
        }

        model.settings.replayBufferPreferredBufferLength = updatedConfiguration.bufferLength
        model.settings.replayBufferConfiguration = updatedConfiguration
        Task {
            await model.reconcileReplayBufferSettings()
        }
    }

    func replayBufferLengthLabel(_ seconds: TimeInterval) -> String {
        switch Int(seconds) {
        case 30:
            "30 Seconds"
        case 60:
            "1 Minute"
        case 120:
            "2 Minutes"
        case 300:
            "5 Minutes"
        default:
            "\(Int(seconds)) Seconds"
        }
    }

    func notchAutoCollapseLabel(_ seconds: TimeInterval) -> String {
        switch Int(seconds) {
        case 0:
            "Immediately"
        case 3:
            "3 Seconds"
        case 6:
            "6 Seconds"
        case 10:
            "10 Seconds"
        default:
            "\(Int(seconds)) Seconds"
        }
    }
}
