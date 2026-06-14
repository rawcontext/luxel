import AppKit
import LuxelCore
import SwiftUI

@MainActor
final class RecordingFramePanelController {
    private var panels: [NSPanel] = []
    private var registrationID: UUID?
    private var exclusionRegistry: CaptureExclusionRegistry?

    func present(
        for request: RecordingRequest,
        availableTargets: [CaptureTargetOption],
        exclusionRegistry: CaptureExclusionRegistry
    ) async {
        await close()

        let frames = frameRects(for: request.target, availableTargets: availableTargets)
        guard !frames.isEmpty else {
            return
        }

        self.exclusionRegistry = exclusionRegistry
        panels = frames.map(makePanel(frame:))
        panels.forEach { $0.orderFrontRegardless() }

        let windowIDs = panels.compactMap { panel -> UInt32? in
            guard panel.windowNumber > 0 else {
                return nil
            }

            return UInt32(panel.windowNumber)
        }
        registrationID = await exclusionRegistry.register(windowIDs: windowIDs)
    }

    func close() async {
        if let registrationID, let exclusionRegistry {
            await exclusionRegistry.unregister(registrationID)
        }

        panels.forEach { $0.close() }
        panels = []
        self.registrationID = nil
        self.exclusionRegistry = nil
    }

    private func makePanel(frame: NSRect) -> NSPanel {
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: RecordingFrameView())
        return panel
    }

    private func frameRects(
        for target: CaptureTarget,
        availableTargets: [CaptureTargetOption]
    ) -> [NSRect] {
        switch target {
        case .display(let displayID):
            return displayFrame(displayID: displayID, availableTargets: availableTargets)
                .map { [$0.screenFrame] } ?? []

        case .area(let displayID, let rect):
            guard let displayFrame = displayFrame(displayID: displayID, availableTargets: availableTargets) else {
                return []
            }

            return [screenRect(fromBottomLeftLocalRect: rect, in: displayFrame)]

        case .window(let id):
            guard let windowTarget = availableTargets.first(where: { $0.target == .window(id: id) }),
                  let windowFrame = windowTarget.frame,
                  let displayFrame = displayFrame(containing: windowFrame, availableTargets: availableTargets) else {
                return []
            }

            return [screenRect(fromTopLeftGlobalRect: windowFrame, in: displayFrame)]
        }
    }

    private func displayFrame(
        displayID: DisplayID,
        availableTargets: [CaptureTargetOption]
    ) -> RecordingDisplayFrame? {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }),
              let target = availableTargets.first(where: { $0.target == .display(displayID) }) else {
            return nil
        }

        return RecordingDisplayFrame(
            screenFrame: screen.frame,
            pixelSize: target.pixelSize,
            globalFrame: target.frame
        )
    }

    private func displayFrame(
        containing rect: CaptureRect,
        availableTargets: [CaptureTargetOption]
    ) -> RecordingDisplayFrame? {
        let centerX = rect.x + rect.width / 2
        let centerY = rect.y + rect.height / 2

        guard let displayTarget = availableTargets.first(where: { target in
            guard case .display(let displayID) = target.target,
                  let frame = target.frame else {
                return false
            }

            return centerX >= frame.x
                && centerX <= frame.x + frame.width
                && centerY >= frame.y
                && centerY <= frame.y + frame.height
                && NSScreen.screens.contains(where: { $0.displayID == displayID })
        }),
            case .display(let displayID) = displayTarget.target else {
            return nil
        }

        return displayFrame(displayID: displayID, availableTargets: availableTargets)
    }

    private func screenRect(
        fromBottomLeftLocalRect rect: CaptureRect,
        in display: RecordingDisplayFrame
    ) -> NSRect {
        NSRect(
            x: display.screenFrame.minX + CGFloat(rect.x) * display.xScale,
            y: display.screenFrame.minY + CGFloat(rect.y) * display.yScale,
            width: CGFloat(rect.width) * display.xScale,
            height: CGFloat(rect.height) * display.yScale
        )
    }

    private func screenRect(
        fromTopLeftGlobalRect rect: CaptureRect,
        in display: RecordingDisplayFrame
    ) -> NSRect {
        guard let globalFrame = display.globalFrame else {
            return .zero
        }

        let localX = rect.x - globalFrame.x
        let localY = rect.y - globalFrame.y
        return NSRect(
            x: display.screenFrame.minX + CGFloat(localX) * display.xScale,
            y: display.screenFrame.maxY - CGFloat(localY + rect.height) * display.yScale,
            width: CGFloat(rect.width) * display.xScale,
            height: CGFloat(rect.height) * display.yScale
        )
    }
}

private struct RecordingDisplayFrame {
    let screenFrame: NSRect
    let pixelSize: PixelSize
    let globalFrame: CaptureRect?

    var xScale: CGFloat {
        screenFrame.width / CGFloat(pixelSize.width)
    }

    var yScale: CGFloat {
        screenFrame.height / CGFloat(pixelSize.height)
    }
}

private struct RecordingFrameView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .strokeBorder(.red.opacity(0.86), lineWidth: 3)
            .background(Color.clear)
            .padding(2)
            .allowsHitTesting(false)
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
