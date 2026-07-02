import AppKit
import Foundation

@MainActor
public final class AppKitCommandLineToolInstallDestinationPicker:
    CommandLineToolInstallDestinationPicker {
    private let bookmarkCreator: any BookmarkedDirectoryBookmarkCreator

    public init(
        bookmarkCreator: any BookmarkedDirectoryBookmarkCreator = FoundationBookmarkCreator()
    ) {
        self.bookmarkCreator = bookmarkCreator
    }

    public func chooseInstallDirectory(defaultDirectory: URL) throws -> BookmarkedDirectory? {
        let panel = NSOpenPanel()
        panel.directoryURL = existingDirectory(for: defaultDirectory)
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = LuxelLocalization.string(
            "panel.commandLineInstall.title",
            defaultValue: "Choose Command Line Tool Folder")
        panel.message = LuxelLocalization.string(
            "panel.commandLineInstall.message",
            defaultValue: "Luxel will create a luxel command in the selected folder.")
        panel.prompt = LuxelLocalization.string("common.install", defaultValue: "Install")

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        return try bookmarkCreator.bookmarkDirectory(at: url)
    }

    private func existingDirectory(for defaultDirectory: URL) -> URL {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: defaultDirectory.path, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return defaultDirectory
        }

        return FileManager.default.homeDirectoryForCurrentUser
    }
}
