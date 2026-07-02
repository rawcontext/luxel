import AppKit
import LuxelCore

@MainActor
enum CaptureTargetScreenRectResolver {
    static func rects(
        for target: CaptureTarget,
        availableTargets: [CaptureTargetOption]
    ) -> [NSRect] {
        rect(for: target, availableTargets: availableTargets).map { [$0] } ?? []
    }

    static func rect(
        for target: CaptureTarget,
        availableTargets: [CaptureTargetOption]
    ) -> NSRect? {
        switch target {
        case .display(let displayID):
            return displayFrame(displayID: displayID, availableTargets: availableTargets)?.screenFrame

        case .area(let displayID, let rect):
            guard
                let displayFrame = displayFrame(displayID: displayID, availableTargets: availableTargets)
            else {
                return nil
            }

            return screenRect(fromTopLeftLocalRect: rect, in: displayFrame)

        case .window(let id):
            guard let windowTarget = availableTargets.first(where: { $0.target == .window(id: id) }),
                  let windowFrame = windowTarget.frame,
                  let displayFrame = displayFrame(containing: windowFrame, availableTargets: availableTargets)
            else {
                return nil
            }

            return screenRect(fromTopLeftGlobalRect: windowFrame, in: displayFrame)
        }
    }

    private static func displayFrame(
        displayID: DisplayID,
        availableTargets: [CaptureTargetOption]
    ) -> CaptureTargetDisplayScreenFrame? {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == displayID }),
              let target = availableTargets.first(where: { $0.target == .display(displayID) })
        else {
            return nil
        }

        return CaptureTargetDisplayScreenFrame(
            screenFrame: screen.frame,
            pixelSize: target.pixelSize,
            globalFrame: target.frame
        )
    }

    private static func displayFrame(
        containing rect: CaptureRect,
        availableTargets: [CaptureTargetOption]
    ) -> CaptureTargetDisplayScreenFrame? {
        let centerX = rect.originX + rect.width / 2
        let centerY = rect.originY + rect.height / 2

        guard
            let displayTarget = availableTargets.first(where: { target in
                guard case .display(let displayID) = target.target,
                      let frame = target.frame
                else {
                    return false
                }

                return centerX >= frame.originX
                    && centerX <= frame.originX + frame.width
                    && centerY >= frame.originY
                    && centerY <= frame.originY + frame.height
                    && NSScreen.screens.contains(where: { $0.displayID == displayID })
            }),
            case .display(let displayID) = displayTarget.target
        else {
            return nil
        }

        return displayFrame(displayID: displayID, availableTargets: availableTargets)
    }

    private static func screenRect(
        fromTopLeftLocalRect rect: CaptureRect,
        in display: CaptureTargetDisplayScreenFrame
    ) -> NSRect {
        NSRect(
            x: display.screenFrame.minX + CGFloat(rect.originX) * display.xScale,
            y: display.screenFrame.maxY - CGFloat(rect.originY + rect.height) * display.yScale,
            width: CGFloat(rect.width) * display.xScale,
            height: CGFloat(rect.height) * display.yScale
        )
    }

    private static func screenRect(
        fromTopLeftGlobalRect rect: CaptureRect,
        in display: CaptureTargetDisplayScreenFrame
    ) -> NSRect {
        guard let globalFrame = display.globalFrame else {
            return .zero
        }

        let localX = rect.originX - globalFrame.originX
        let localY = rect.originY - globalFrame.originY
        return NSRect(
            x: display.screenFrame.minX + CGFloat(localX) * display.xScale,
            y: display.screenFrame.maxY - CGFloat(localY + rect.height) * display.yScale,
            width: CGFloat(rect.width) * display.xScale,
            height: CGFloat(rect.height) * display.yScale
        )
    }
}

private struct CaptureTargetDisplayScreenFrame {
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
