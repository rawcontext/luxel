import Foundation

public struct BookmarkedDirectory: Codable, Equatable, Sendable {
    public var url: URL
    public var bookmarkData: Data
    public var accessState: BookmarkedDirectoryAccessState

    public init(
        url: URL,
        bookmarkData: Data,
        accessState: BookmarkedDirectoryAccessState = .resolved
    ) {
        self.url = url
        self.bookmarkData = bookmarkData
        self.accessState = accessState
    }

    public var needsRefresh: Bool {
        accessState == .stale || accessState == .revoked
    }
}

public enum BookmarkedDirectoryAccessState: String, Codable, Equatable, Sendable {
    case resolved
    case stale
    case revoked
}
