import AppKit
import LuxelCore
import SwiftUI

@MainActor
final class LuxelCropperPanelController {
    private let targetService: CaptureTargetService
    private let audioLevelMonitorFactory: () -> any AudioLevelMonitor
    private var panels: [NSPanel] = []
    private var audioLevelModel: LuxelAudioLevelModel?
    private var audioLevelTask: Task<Void, Never>?

    init(
        targetService: CaptureTargetService = CaptureTargetService(
            catalog: CachedCaptureTargetCatalog(upstream: ScreenCaptureKitCaptureTargetCatalog())
        ),
        audioLevelMonitorFactory: @escaping () -> any AudioLevelMonitor = {
            AVCaptureAudioLevelMonitor()
        }
    ) {
        self.targetService = targetService
        self.audioLevelMonitorFactory = audioLevelMonitorFactory
    }

    func show(
        initialMode: LuxelCropperMode = .video,
        countdownDuration: TimeInterval? = nil,
        stopAfterDuration: TimeInterval? = nil,
        audioLevelConfiguration: CropperAudioLevelConfiguration? = nil,
        cameraConfiguration: CropperCameraConfiguration = CropperCameraConfiguration(
            selectedDeviceID: nil,
            devices: [],
            previewStyle: CameraPreviewStyle()
        ),
        quickRecordingConfiguration: CropperQuickRecordingConfiguration = CropperQuickRecordingConfiguration(
            activePresetID: nil,
            presets: []
        ),
        selectionPresetConfiguration: CropperSelectionPresetConfiguration = CropperSelectionPresetConfiguration(
            sizePresets: CaptureSizePreset.builtInDefaults
        ),
        restoreSelectionConfiguration: CropperRestoreSelectionConfiguration = .disabled,
        loupeAlwaysOn: Bool = false,
        dimOtherDisplays: Bool = false,
        showsNotificationReminder: Bool = false,
        onCountdownDurationChange: @escaping @MainActor (TimeInterval?) -> Void = { _ in },
        onStopAfterDurationChange: @escaping @MainActor (TimeInterval?) -> Void = { _ in },
        onCameraSelectionChange: @escaping @MainActor (String?) -> Void = { _ in },
        onCameraPreviewStyleChange: @escaping @MainActor (CameraPreviewStyle) -> Void = { _ in },
        onNotificationReminderDismiss: @escaping @MainActor () -> Void = {},
        onCaptureScreenshot: @escaping @MainActor (CaptureSelectionDraft) -> Void = { _ in },
        onQuickSelect: @escaping @MainActor (CaptureSelectionDraft, UUID) -> Void = { _, _ in },
        onSelect: @escaping @MainActor (CaptureSelectionDraft) -> Void
    ) {
        close()

        Task { @MainActor in
            do {
                let displays = try await targetService.availableDisplays()
                let targets = try await targetService.availableTargets()
                let presentation = CropperPanelPresentation(
                    initialMode: initialMode,
                    countdownDuration: countdownDuration,
                    stopAfterDuration: stopAfterDuration,
                    audioLevelConfiguration: audioLevelConfiguration,
                    cameraConfiguration: cameraConfiguration,
                    quickRecordingConfiguration: quickRecordingConfiguration,
                    selectionPresetConfiguration: selectionPresetConfiguration,
                    restoreSelectionConfiguration: restoreSelectionConfiguration,
                    loupeAlwaysOn: loupeAlwaysOn,
                    dimOtherDisplays: dimOtherDisplays,
                    showsNotificationReminder: showsNotificationReminder,
                    onCountdownDurationChange: onCountdownDurationChange,
                    onStopAfterDurationChange: onStopAfterDurationChange,
                    onCameraSelectionChange: onCameraSelectionChange,
                    onCameraPreviewStyleChange: onCameraPreviewStyleChange,
                    onNotificationReminderDismiss: onNotificationReminderDismiss,
                    onCaptureScreenshot: onCaptureScreenshot,
                    onQuickSelect: onQuickSelect,
                    onSelect: onSelect
                )
                present(
                    displays: displays,
                    targets: targets,
                    presentation: presentation
                )
            } catch {
                NSSound.beep()
            }
        }
    }

    func close() {
        audioLevelTask?.cancel()
        audioLevelTask = nil
        audioLevelModel?.stop()
        audioLevelModel = nil
        panels.forEach { $0.close() }
        panels = []
    }

    private func present(
        displays: [DisplayBounds],
        targets: [CaptureTargetOption],
        presentation: CropperPanelPresentation
    ) {
        let displaysByID = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, $0) })
        let sharedAudioLevelModel = presentation.audioLevelConfiguration.map {
            LuxelAudioLevelModel(
                deviceID: $0.deviceID,
                monitor: audioLevelMonitorFactory()
            )
        }

        audioLevelModel = sharedAudioLevelModel
        if let sharedAudioLevelModel {
            audioLevelTask = Task {
                await sharedAudioLevelModel.watch()
            }
        }

        let displayFocus = CropperDisplayFocus()

        for screen in NSScreen.screens {
            guard let displayID = screen.displayID,
                  let display = displaysByID[displayID] else {
                continue
            }

            let model = LuxelCropperModel(
                display: display,
                mode: presentation.initialMode,
                countdownDuration: presentation.countdownDuration,
                stopAfterDuration: presentation.stopAfterDuration,
                selectionPresetConfiguration: presentation.selectionPresetConfiguration,
                initialSelection: presentation.restoreSelectionConfiguration.selection(for: display, targets: targets),
                windowSnapFrames: CaptureWindowSnapFrameResolver.windowFrames(
                    on: display,
                    from: targets
                ),
                loupeAlwaysOn: presentation.loupeAlwaysOn,
                dimOtherDisplays: presentation.dimOtherDisplays,
                displayFocus: displayFocus,
                onCountdownDurationChange: presentation.onCountdownDurationChange,
                onStopAfterDurationChange: presentation.onStopAfterDurationChange
            )
            let panel = NSPanel(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.contentView = NSHostingView(
                rootView: LuxelCropperView(
                    model: model,
                    audioLevelModel: sharedAudioLevelModel,
                    cameraConfiguration: presentation.cameraConfiguration,
                    quickRecordingConfiguration: presentation.quickRecordingConfiguration,
                    showsNotificationReminder: presentation.showsNotificationReminder,
                    onCameraSelectionChange: presentation.onCameraSelectionChange,
                    onCameraPreviewStyleChange: presentation.onCameraPreviewStyleChange,
                    onNotificationReminderDismiss: presentation.onNotificationReminderDismiss,
                    onCancel: { [weak self] in
                        self?.close()
                    },
                    onSelect: { [weak self] draft in
                        self?.close()
                        presentation.onSelect(draft)
                    },
                    onQuickSelect: { [weak self] draft, presetID in
                        self?.close()
                        presentation.onQuickSelect(draft, presetID)
                    },
                    onCaptureScreenshot: { [weak self] draft in
                        self?.close()
                        presentation.onCaptureScreenshot(draft)
                    }
                )
            )
            panel.makeKeyAndOrderFront(nil)
            panels.append(panel)
        }

        if panels.isEmpty {
            NSSound.beep()
        } else {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }
}

private struct CropperPanelPresentation {
    let initialMode: LuxelCropperMode
    let countdownDuration: TimeInterval?
    let stopAfterDuration: TimeInterval?
    let audioLevelConfiguration: CropperAudioLevelConfiguration?
    let cameraConfiguration: CropperCameraConfiguration
    let quickRecordingConfiguration: CropperQuickRecordingConfiguration
    let selectionPresetConfiguration: CropperSelectionPresetConfiguration
    let restoreSelectionConfiguration: CropperRestoreSelectionConfiguration
    let loupeAlwaysOn: Bool
    let dimOtherDisplays: Bool
    let showsNotificationReminder: Bool
    let onCountdownDurationChange: @MainActor (TimeInterval?) -> Void
    let onStopAfterDurationChange: @MainActor (TimeInterval?) -> Void
    let onCameraSelectionChange: @MainActor (String?) -> Void
    let onCameraPreviewStyleChange: @MainActor (CameraPreviewStyle) -> Void
    let onNotificationReminderDismiss: @MainActor () -> Void
    let onCaptureScreenshot: @MainActor (CaptureSelectionDraft) -> Void
    let onQuickSelect: @MainActor (CaptureSelectionDraft, UUID) -> Void
    let onSelect: @MainActor (CaptureSelectionDraft) -> Void
}

private extension NSScreen {
    var displayID: DisplayID? {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        return DisplayID(screenNumber.uint32Value)
    }
}
