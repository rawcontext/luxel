import Foundation

public protocol FileSystem: Sendable {
    func fileExists(at url: URL) -> Bool
    func removeFile(at url: URL) throws
}
