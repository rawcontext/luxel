import Foundation

@MainActor
public protocol FrameGrabDestinationClient: AnyObject {
    func copyImageToPasteboard(_ imageData: FrameGrabImageData) throws
}
