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
            catalog: ScreenCaptureKitCaptureTargetCatalog()
        ),
        audioLevelMonitorFactory: @escaping () -> any AudioLevelMonitor = {
            AVCaptureAudioLevelMonitor()
        }
    ) {
        self.targetService = targetService
        self.audioLevelMonitorFactory = audioLevelMonitorFactory
    }

    func show(
        stopAfterDuration: TimeInterval? = nil,
        audioLevelConfiguration: CropperAudioLevelConfiguration? = nil,
        onStopAfterDurationChange: @escaping @MainActor (TimeInterval?) -> Void = { _ in },
        onSelect: @escaping @MainActor (CaptureSelectionDraft) -> Void
    ) {
        close()

        Task { @MainActor in
            do {
                let displays = try await targetService.availableDisplays()
                present(
                    displays: displays,
                    stopAfterDuration: stopAfterDuration,
                    audioLevelConfiguration: audioLevelConfiguration,
                    onStopAfterDurationChange: onStopAfterDurationChange,
                    onSelect: onSelect
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
        stopAfterDuration: TimeInterval?,
        audioLevelConfiguration: CropperAudioLevelConfiguration?,
        onStopAfterDurationChange: @escaping @MainActor (TimeInterval?) -> Void,
        onSelect: @escaping @MainActor (CaptureSelectionDraft) -> Void
    ) {
        let displaysByID = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, $0) })
        let sharedAudioLevelModel = audioLevelConfiguration.map {
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

        for screen in NSScreen.screens {
            guard let displayID = screen.displayID,
                  let display = displaysByID[displayID] else {
                continue
            }

            let model = LuxelCropperModel(
                display: display,
                stopAfterDuration: stopAfterDuration,
                onStopAfterDurationChange: onStopAfterDurationChange
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
                    onCancel: { [weak self] in
                        self?.close()
                    },
                    onSelect: { [weak self] draft in
                        self?.close()
                        onSelect(draft)
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

private extension NSScreen {
    var displayID: DisplayID? {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        return DisplayID(screenNumber.uint32Value)
    }
}
