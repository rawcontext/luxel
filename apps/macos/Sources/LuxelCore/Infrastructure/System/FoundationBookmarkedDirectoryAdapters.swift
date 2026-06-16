import Foundation

public struct FoundationBookmarkCreator: BookmarkedDirectoryBookmarkCreator {
    public init() {}

    public func bookmarkDirectory(at url: URL) throws -> BookmarkedDirectory {
        let bookmarkData = try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        return BookmarkedDirectory(url: url, bookmarkData: bookmarkData)
    }
}

public struct FoundationBookmarkedDirectoryResolver: BookmarkedDirectoryResolver {
    public init() {}

    public func resolve(_ directory: BookmarkedDirectory) throws -> BookmarkedDirectoryResolution {
        var isStale = false
        let resolvedURL = try URL(
            resolvingBookmarkData: directory.bookmarkData,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )

        return BookmarkedDirectoryResolution(
            url: resolvedURL,
            bookmarkData: directory.bookmarkData,
            isStale: isStale
        )
    }
}

public struct URLSecurityScopedResourceAccess: SecurityScopedResourceAccess {
    public init() {}

    public func startAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    public func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}
