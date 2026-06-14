import Foundation

@MainActor
public protocol ScreenshotDestinationClient: AnyObject {
    func copyImageToPasteboard(_ imageData: ImageData) throws
    func openWithDefaultApp(_ fileURL: URL) throws
}
