import Foundation

public struct LocalFileSystem: FileSystem {
    public init() {}

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func removeFile(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}
