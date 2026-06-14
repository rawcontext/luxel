import Foundation

public protocol FileSystem: Sendable {
    func fileExists(at url: URL) -> Bool
    func createDirectory(at url: URL) throws
    func copyFile(from sourceURL: URL, to destinationURL: URL) throws
    func writeData(_ data: Data, to url: URL) throws
    func removeFile(at url: URL) throws
    func trashItem(at url: URL) throws
}
