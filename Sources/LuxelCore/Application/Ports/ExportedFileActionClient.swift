import Foundation

@MainActor
public protocol ExportedFileActionClient: AnyObject {
    func chooseSaveDestination(suggestedFileName: String) -> URL?
    func chooseOutputDirectory(currentDirectory: URL) -> URL?
    func chooseApplicationForOpening(fileURL: URL) -> URL?
    func copyFile(from sourceURL: URL, to destinationURL: URL) throws
    func copyFileToPasteboard(_ fileURL: URL)
    func copyPathToPasteboard(_ fileURL: URL)
    func copyTextToPasteboard(_ text: String)
    func revealInFinder(_ fileURL: URL)
    func openWithDefaultApp(_ fileURL: URL)
    func open(_ fileURL: URL, withApplicationAt applicationURL: URL)
}
