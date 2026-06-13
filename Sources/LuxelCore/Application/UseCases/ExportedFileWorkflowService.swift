import Foundation

@MainActor
public final class ExportedFileWorkflowService {
    private let client: any ExportedFileActionClient

    public init(client: any ExportedFileActionClient) {
        self.client = client
    }

    public func saveAs(_ fileURL: URL, suggestedFileName: String? = nil) throws -> URL? {
        let destinationURL = client.chooseSaveDestination(
            suggestedFileName: suggestedFileName ?? fileURL.lastPathComponent
        )

        guard let destinationURL else {
            return nil
        }

        try client.copyFile(from: fileURL, to: destinationURL)
        return destinationURL
    }

    public func chooseOutputDirectory(currentDirectory: URL) -> URL? {
        client.chooseOutputDirectory(currentDirectory: currentDirectory)
    }

    public func copyFile(_ fileURL: URL) {
        client.copyFileToPasteboard(fileURL)
    }

    public func copyPath(_ fileURL: URL) {
        client.copyPathToPasteboard(fileURL)
    }

    public func copyText(_ text: String) {
        client.copyTextToPasteboard(text)
    }

    public func revealInFinder(_ fileURL: URL) {
        client.revealInFinder(fileURL)
    }

    public func openWithDefaultApp(_ fileURL: URL) {
        client.openWithDefaultApp(fileURL)
    }

    public func openWithApplication(_ fileURL: URL) -> Bool {
        guard let applicationURL = client.chooseApplicationForOpening(fileURL: fileURL) else {
            return false
        }

        client.open(fileURL, withApplicationAt: applicationURL)
        return true
    }
}
