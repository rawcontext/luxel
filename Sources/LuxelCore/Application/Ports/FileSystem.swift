import Foundation

public protocol FileSystem: Sendable {
    func fileExists(at url: URL) -> Bool
    func createDirectory(at url: URL) throws
    func copyFile(from sourceURL: URL, to destinationURL: URL) throws
    func readData(at url: URL) throws -> Data
    func writeData(_ data: Data, to url: URL) throws
    func removeFile(at url: URL) throws
    func trashItem(at url: URL) throws
}

public extension FileSystem {
    func readData(at url: URL) throws -> Data {
        throw FileSystemError.unsupportedRead(url)
    }
}

public enum FileSystemError: Error, Equatable, Sendable {
    case unsupportedRead(URL)
}
