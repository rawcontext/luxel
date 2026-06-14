import Foundation

public protocol ScreenshotFileWriter: Sendable {
    func write(_ imageData: ImageData, to fileURL: URL) throws
}
