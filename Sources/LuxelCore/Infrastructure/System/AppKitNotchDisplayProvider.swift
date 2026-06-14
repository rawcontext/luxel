import AppKit
import CoreGraphics

@MainActor
public final class AppKitNotchDisplayProvider: NotchDisplayProvider {
    public init() {}

    public func displays() -> [NotchDisplayDescriptor] {
        NSScreen.screens.compactMap { screen in
            Self.descriptor(
                displayID: screen.displayID,
                frame: screen.frame,
                safeAreaInsets: screen.safeAreaInsets,
                auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
                auxiliaryTopRightArea: screen.auxiliaryTopRightArea,
                isBuiltIn: screen.displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false
            )
        }
    }

    nonisolated public static func descriptor(
        displayID: CGDirectDisplayID?,
        frame: CGRect,
        safeAreaInsets: NSEdgeInsets,
        auxiliaryTopLeftArea: CGRect?,
        auxiliaryTopRightArea: CGRect?,
        isBuiltIn: Bool,
        isVisible: Bool = true
    ) -> NotchDisplayDescriptor? {
        guard let displayID,
              let frame = notchRect(from: frame),
              let safeAreaInsets = notchInsets(from: safeAreaInsets) else {
            return nil
        }

        return NotchDisplayDescriptor(
            displayID: DisplayID(displayID),
            frame: frame,
            safeAreaInsets: safeAreaInsets,
            auxiliaryTopLeftArea: auxiliaryTopLeftArea.flatMap(notchRect(from:)),
            auxiliaryTopRightArea: auxiliaryTopRightArea.flatMap(notchRect(from:)),
            isBuiltIn: isBuiltIn,
            isVisible: isVisible
        )
    }

    nonisolated private static func notchRect(from rect: CGRect) -> NotchScreenRect? {
        try? NotchScreenRect(
            x: rect.origin.x,
            y: rect.origin.y,
            width: rect.width,
            height: rect.height
        )
    }

    nonisolated private static func notchInsets(from insets: NSEdgeInsets) -> NotchSafeAreaInsets? {
        try? NotchSafeAreaInsets(
            top: insets.top,
            left: insets.left,
            bottom: insets.bottom,
            right: insets.right
        )
    }
}

private extension NSScreen {
    var displayID: CGDirectDisplayID? {
        guard let screenNumber = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        return screenNumber.uint32Value
    }
}
