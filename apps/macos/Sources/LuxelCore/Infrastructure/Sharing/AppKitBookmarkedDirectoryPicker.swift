import AppKit
import Foundation

@MainActor
public final class AppKitBookmarkedDirectoryPicker: BookmarkedDirectoryPicker {
    private let bookmarkCreator: any BookmarkedDirectoryBookmarkCreator

    public init(
        bookmarkCreator: any BookmarkedDirectoryBookmarkCreator = FoundationBookmarkCreator()
    ) {
        self.bookmarkCreator = bookmarkCreator
    }

    public func chooseDirectory(currentDirectory: URL) throws -> BookmarkedDirectory? {
        let panel = NSOpenPanel()
        panel.directoryURL = currentDirectory
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = LuxelLocalization.string(
            "panel.recordingFolder.title",
            defaultValue: "Choose Recording Folder")
        panel.prompt = LuxelLocalization.string("common.choose", defaultValue: "Choose")

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        return try bookmarkCreator.bookmarkDirectory(at: url)
    }
}
