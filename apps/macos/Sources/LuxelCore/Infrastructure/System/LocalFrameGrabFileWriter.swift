import Foundation

public struct LocalFrameGrabFileWriter: FrameGrabFileWriter {
    public init() {}

    public func write(_ imageData: FrameGrabImageData, to fileURL: URL) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try imageData.data.write(to: fileURL, options: .atomic)
    }
}
