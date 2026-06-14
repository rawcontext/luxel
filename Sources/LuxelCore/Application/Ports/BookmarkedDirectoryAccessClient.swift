import Foundation

public protocol BookmarkedDirectoryResolver: Sendable {
    func resolve(_ directory: BookmarkedDirectory) throws -> BookmarkedDirectoryResolution
}

public protocol SecurityScopedResourceAccess: Sendable {
    func startAccessing(_ url: URL) -> Bool
    func stopAccessing(_ url: URL)
}

public struct BookmarkedDirectoryResolution: Equatable, Sendable {
    public let url: URL
    public let bookmarkData: Data
    public let isStale: Bool

    public init(url: URL, bookmarkData: Data, isStale: Bool) {
        self.url = url
        self.bookmarkData = bookmarkData
        self.isStale = isStale
    }
}
