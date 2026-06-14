import AppKit

@MainActor
public final class AppKitPointerDisplayProvider: PointerDisplayProvider {
    public init() {}

    public func displayIDContainingPointer() -> DisplayID? {
        let mouseLocation = NSEvent.mouseLocation

        return NSScreen.screens
            .first { $0.frame.contains(mouseLocation) }?
            .displayID
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
