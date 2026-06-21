import Foundation

public protocol FrameGrabFileWriter: Sendable {
    func write(_ imageData: FrameGrabImageData, to fileURL: URL) throws
}
