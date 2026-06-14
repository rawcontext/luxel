import Foundation

public struct LocalScreenshotFileWriter: ScreenshotFileWriter {
    public init() {}

    public func write(_ imageData: ImageData, to fileURL: URL) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try imageData.data.write(to: fileURL, options: .atomic)
    }
}
