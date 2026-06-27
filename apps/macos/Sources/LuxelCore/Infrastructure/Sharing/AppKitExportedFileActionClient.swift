import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
public final class AppKitExportedFileActionClient: ExportedFileActionClient {
    public init() {}

    public func chooseSaveDestination(suggestedFileName: String) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFileName
        panel.canCreateDirectories = true
        panel.title = LuxelLocalization.string("panel.saveExport.title", defaultValue: "Save Export")
        panel.prompt = LuxelLocalization.string("common.save", defaultValue: "Save")

        return panel.runModal() == .OK ? panel.url : nil
    }

    public func chooseOutputDirectory(currentDirectory: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.directoryURL = currentDirectory
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = LuxelLocalization.string(
            "panel.exportFolder.title",
            defaultValue: "Choose Export Folder")
        panel.prompt = LuxelLocalization.string("common.choose", defaultValue: "Choose")

        return panel.runModal() == .OK ? panel.url : nil
    }

    public func chooseApplicationForOpening(fileURL: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.title = LuxelLocalization.string("panel.openWith.title", defaultValue: "Open With")
        panel.message = LuxelLocalization.format(
            "panel.openWith.message",
            defaultValue: "Choose an app to open %@.",
            fileURL.lastPathComponent)
        panel.prompt = LuxelLocalization.string("common.open", defaultValue: "Open")

        return panel.runModal() == .OK ? panel.url : nil
    }

    public func copyFile(from sourceURL: URL, to destinationURL: URL) throws {
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
    }

    public func copyFileToPasteboard(_ fileURL: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([fileURL as NSURL])
    }

    public func copyPathToPasteboard(_ fileURL: URL) {
        copyTextToPasteboard(fileURL.path)
    }

    public func copyTextToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    public func revealInFinder(_ fileURL: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    public func openWithDefaultApp(_ fileURL: URL) {
        NSWorkspace.shared.open(fileURL)
    }

    public func open(_ fileURL: URL, withApplicationAt applicationURL: URL) {
        NSWorkspace.shared.open(
            [fileURL],
            withApplicationAt: applicationURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}
