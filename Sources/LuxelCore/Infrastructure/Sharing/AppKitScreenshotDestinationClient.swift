import AppKit
import Foundation

@MainActor
public final class AppKitScreenshotDestinationClient: ScreenshotDestinationClient {
    public init() {}

    public func copyImageToPasteboard(_ imageData: ImageData) throws {
        guard let image = NSImage(data: imageData.data) else {
            throw AppKitScreenshotDestinationClientError.invalidImageData
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        guard pasteboard.writeObjects([image]) else {
            throw AppKitScreenshotDestinationClientError.pasteboardWriteFailed
        }

        pasteboard.setData(imageData.data, forType: imageData.format.pasteboardType)
    }

    public func openWithDefaultApp(_ fileURL: URL) throws {
        guard NSWorkspace.shared.open(fileURL) else {
            throw AppKitScreenshotDestinationClientError.openFailed(fileURL)
        }
    }
}

public enum AppKitScreenshotDestinationClientError: Error, Equatable {
    case invalidImageData
    case pasteboardWriteFailed
    case openFailed(URL)
}

private extension ScreenshotFormat {
    var pasteboardType: NSPasteboard.PasteboardType {
        switch self {
        case .png:
            NSPasteboard.PasteboardType("public.png")
        case .jpeg:
            NSPasteboard.PasteboardType("public.jpeg")
        case .heic:
            NSPasteboard.PasteboardType("public.heic")
        }
    }
}
