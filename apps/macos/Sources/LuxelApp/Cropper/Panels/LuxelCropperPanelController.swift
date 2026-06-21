import AppKit
import LuxelCore
import SwiftUI

@MainActor
final class LuxelCropperPanelController {
    private static let panelLevel = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue - 1)

    private let targetService: CaptureTargetService
    private let exclusionRegistry: CaptureExclusionRegistry
    private var panels: [NSPanel] = []
    private var exclusionRegistrationID: UUID?

    init(
        targetService: CaptureTargetService = CaptureTargetService(
            catalog: CachedCaptureTargetCatalog(upstream: ScreenCaptureKitCaptureTargetCatalog())
        ),
        exclusionRegistry: CaptureExclusionRegistry = CaptureExclusionRegistry()
    ) {
        self.targetService = targetService
        self.exclusionRegistry = exclusionRegistry
    }

    func show(
        countdownDuration: TimeInterval? = nil,
        stopAfterDuration: TimeInterval? = nil,
        canRecordAudio: Bool = false,
        cameraConfiguration: CropperCameraConfiguration = CropperCameraConfiguration(
            selectedDeviceID: nil,
            devices: [],
            previewStyle: CameraPreviewStyle()
        ),
        quickRecordingConfiguration: CropperQuickRecordingConfiguration =
            CropperQuickRecordingConfiguration(
                activePresetID: nil,
                presets: []
            ),
        selectionPresetConfiguration: CropperSelectionPresetConfiguration =
            CropperSelectionPresetConfiguration(
                sizePresets: CaptureSizePreset.builtInDefaults
            ),
        restoreSelectionConfiguration: CropperRestoreSelectionConfiguration = .disabled,
        recordAudio: Bool = false,
        loupeAlwaysOn: Bool = false,
        dimOtherDisplays: Bool = false,
        showsNotificationReminder: Bool = false,
        onCountdownDurationChange: @escaping @MainActor (TimeInterval?) -> Void = { _ in },
        onStopAfterDurationChange: @escaping @MainActor (TimeInterval?) -> Void = { _ in },
        onRecordAudioChange: @escaping @MainActor (Bool) -> Void = { _ in },
        onCameraSelectionChange: @escaping @MainActor (String?) -> Void = { _ in },
        onCameraPreviewStyleChange: @escaping @MainActor (CameraPreviewStyle) -> Void = { _ in },
        onNotificationReminderDismiss: @escaping @MainActor () -> Void = {},
        onQuickSelect: @escaping @MainActor (CaptureSelectionDraft, UUID) -> Void = { _, _ in },
        onSelect: @escaping @MainActor (CaptureSelectionDraft) -> Void
    ) {
        close()

        Task { @MainActor in
            do {
                let displays = try await targetService.availableDisplays()
                let targets = try await targetService.availableTargets()
                let presentation = CropperPanelPresentation(
                    countdownDuration: countdownDuration,
                    stopAfterDuration: stopAfterDuration,
                    canRecordAudio: canRecordAudio,
                    cameraConfiguration: cameraConfiguration,
                    quickRecordingConfiguration: quickRecordingConfiguration,
                    selectionPresetConfiguration: selectionPresetConfiguration,
                    restoreSelectionConfiguration: restoreSelectionConfiguration,
                    recordAudio: recordAudio,
                    loupeAlwaysOn: loupeAlwaysOn,
                    dimOtherDisplays: dimOtherDisplays,
                    showsNotificationReminder: showsNotificationReminder,
                    onCountdownDurationChange: onCountdownDurationChange,
                    onStopAfterDurationChange: onStopAfterDurationChange,
                    onRecordAudioChange: onRecordAudioChange,
                    onCameraSelectionChange: onCameraSelectionChange,
                    onCameraPreviewStyleChange: onCameraPreviewStyleChange,
                    onNotificationReminderDismiss: onNotificationReminderDismiss,
                    onQuickSelect: onQuickSelect,
                    onSelect: onSelect
                )
                await present(
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
        panels.forEach { $0.close() }
        panels = []
        if let exclusionRegistrationID {
            self.exclusionRegistrationID = nil
            Task {
                await exclusionRegistry.unregister(exclusionRegistrationID)
            }
        }
    }

    private func present(
        displays: [DisplayBounds],
        targets: [CaptureTargetOption],
        presentation: CropperPanelPresentation
    ) async {
        let displaysByID = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, $0) })
        let displayFocus = CropperDisplayFocus()

        for screen in NSScreen.screens {
            guard let displayID = screen.displayID,
                  let display = displaysByID[displayID]
            else {
                continue
            }

            let model = LuxelCropperModel(
                display: display,
                countdownDuration: presentation.countdownDuration,
                stopAfterDuration: presentation.stopAfterDuration,
                selectionPresetConfiguration: presentation.selectionPresetConfiguration,
                initialSelection: presentation.restoreSelectionConfiguration.selection(
                    for: display, targets: targets),
                windowSnapFrames: CaptureWindowSnapFrameResolver.windowFrames(
                    on: display,
                    from: targets
                ),
                recordAudio: presentation.recordAudio,
                canRecordAudio: presentation.canRecordAudio,
                loupeAlwaysOn: presentation.loupeAlwaysOn,
                dimOtherDisplays: presentation.dimOtherDisplays,
                displayFocus: displayFocus,
                onCountdownDurationChange: presentation.onCountdownDurationChange,
                onStopAfterDurationChange: presentation.onStopAfterDurationChange,
                onRecordAudioChange: { isEnabled in
                    presentation.onRecordAudioChange(isEnabled)
                }
            )
            let panel = LuxelCropperPanel(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            panel.onCancel = { [weak self] in
                self?.close()
            }
            panel.level = Self.panelLevel
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.contentView = NSHostingView(
                rootView: LuxelCropperView(
                    model: model,
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
                    }
                )
            )
            panel.makeKeyAndOrderFront(nil)
            panels.append(panel)
        }

        await registerPanelsForCaptureExclusion()

        if panels.isEmpty {
            NSSound.beep()
        } else {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    private func registerPanelsForCaptureExclusion() async {
        let windowIDs =
            panels
            .map(\.windowNumber)
            .filter { $0 > 0 }
            .map(UInt32.init)

        if let exclusionRegistrationID {
            await exclusionRegistry.register(
                windowIDs: windowIDs, registrationID: exclusionRegistrationID)
        } else {
            exclusionRegistrationID = await exclusionRegistry.register(windowIDs: windowIDs)
        }
    }

}

private struct CropperPanelPresentation {
    let countdownDuration: TimeInterval?
    let stopAfterDuration: TimeInterval?
    let canRecordAudio: Bool
    let cameraConfiguration: CropperCameraConfiguration
    let quickRecordingConfiguration: CropperQuickRecordingConfiguration
    let selectionPresetConfiguration: CropperSelectionPresetConfiguration
    let restoreSelectionConfiguration: CropperRestoreSelectionConfiguration
    let recordAudio: Bool
    let loupeAlwaysOn: Bool
    let dimOtherDisplays: Bool
    let showsNotificationReminder: Bool
    let onCountdownDurationChange: @MainActor (TimeInterval?) -> Void
    let onStopAfterDurationChange: @MainActor (TimeInterval?) -> Void
    let onRecordAudioChange: @MainActor (Bool) -> Void
    let onCameraSelectionChange: @MainActor (String?) -> Void
    let onCameraPreviewStyleChange: @MainActor (CameraPreviewStyle) -> Void
    let onNotificationReminderDismiss: @MainActor () -> Void
    let onQuickSelect: @MainActor (CaptureSelectionDraft, UUID) -> Void
    let onSelect: @MainActor (CaptureSelectionDraft) -> Void
}

private final class LuxelCropperPanel: NSPanel {
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel?()
            return
        }

        super.keyDown(with: event)
    }
}

extension NSScreen {
    fileprivate var displayID: DisplayID? {
        guard
            let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        else {
            return nil
        }

        return DisplayID(screenNumber.uint32Value)
    }
}
