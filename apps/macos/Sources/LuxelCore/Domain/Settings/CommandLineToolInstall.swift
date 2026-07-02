import Foundation

public struct CommandLineToolInstall: Codable, Equatable, Sendable {
    public var linkURL: URL
    public var directoryBookmark: BookmarkedDirectory

    public init(linkURL: URL, directoryBookmark: BookmarkedDirectory) {
        self.linkURL = linkURL
        self.directoryBookmark = directoryBookmark
    }
}
