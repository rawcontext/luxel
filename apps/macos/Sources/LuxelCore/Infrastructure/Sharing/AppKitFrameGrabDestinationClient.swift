import AppKit
import Foundation

@MainActor
public final class AppKitFrameGrabDestinationClient: FrameGrabDestinationClient {
    public init() {}

    public func copyImageToPasteboard(_ imageData: FrameGrabImageData) throws {
        guard let image = NSImage(data: imageData.data) else {
            throw AppKitFrameGrabDestinationClientError.invalidImageData
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        guard pasteboard.writeObjects([image]) else {
            throw AppKitFrameGrabDestinationClientError.pasteboardWriteFailed
        }

        pasteboard.setData(imageData.data, forType: NSPasteboard.PasteboardType("public.png"))
    }
}

public enum AppKitFrameGrabDestinationClientError: Error, Equatable {
    case invalidImageData
    case pasteboardWriteFailed
}
