import AppKit
import LuxelCore
import SwiftUI

@MainActor
final class LuxelCropperPanelController {
    private let targetService: CaptureTargetService
    private var panels: [NSPanel] = []

    init(
        targetService: CaptureTargetService = CaptureTargetService(
            catalog: ScreenCaptureKitCaptureTargetCatalog()
        )
    ) {
        self.targetService = targetService
    }

    func show(onSelect: @escaping @MainActor (CaptureSelectionDraft) -> Void) {
        close()

        Task { @MainActor in
            do {
                let displays = try await targetService.availableDisplays()
                present(displays: displays, onSelect: onSelect)
            } catch {
                NSSound.beep()
            }
        }
    }

    func close() {
        panels.forEach { $0.close() }
        panels = []
    }

    private func present(
        displays: [DisplayBounds],
        onSelect: @escaping @MainActor (CaptureSelectionDraft) -> Void
    ) {
        let displaysByID = Dictionary(uniqueKeysWithValues: displays.map { ($0.id, $0) })

        for screen in NSScreen.screens {
            guard let displayID = screen.displayID,
                  let display = displaysByID[displayID] else {
                continue
            }

            let model = LuxelCropperModel(display: display)
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
