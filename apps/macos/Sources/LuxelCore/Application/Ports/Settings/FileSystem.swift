import Foundation

public protocol FileSystem: Sendable {
    func fileExists(at url: URL) -> Bool
    func createDirectory(at url: URL) throws
    func copyFile(from sourceURL: URL, to destinationURL: URL) throws
    func moveFile(from sourceURL: URL, to destinationURL: URL) throws
    func readData(at url: URL) throws -> Data
    func writeData(_ data: Data, to url: URL) throws
    func removeFile(at url: URL) throws
    func trashItem(at url: URL) throws
}

extension FileSystem {
    public func moveFile(from sourceURL: URL, to destinationURL: URL) throws {
        try copyFile(from: sourceURL, to: destinationURL)
        try removeFile(at: sourceURL)
    }

    public func readData(at url: URL) throws -> Data {
        throw FileSystemError.unsupportedRead(url)
    }
}

public enum FileSystemError: Error, Equatable, Sendable {
    case unsupportedRead(URL)
}
