import Foundation

@MainActor
public protocol BookmarkedDirectoryPicker: AnyObject {
    func chooseDirectory(currentDirectory: URL) throws -> BookmarkedDirectory?
}

public protocol BookmarkedDirectoryBookmarkCreator: Sendable {
    func bookmarkDirectory(at url: URL) throws -> BookmarkedDirectory
}
