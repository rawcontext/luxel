import Foundation
import LuxelCore
import Testing

@MainActor
@Suite("Exported file workflow service")
struct ExportedFileWorkflowServiceTests {
    @Test("saveAs copies to the selected destination")
    func saveAsCopiesToSelectedDestination() throws {
        let sourceURL = URL(fileURLWithPath: "/tmp/source.mp4")
        let destinationURL = URL(fileURLWithPath: "/tmp/destination.mp4")
        let client = FakeExportedFileActionClient(destinationURL: destinationURL)
        let service = ExportedFileWorkflowService(client: client)

        let savedURL = try service.saveAs(sourceURL, suggestedFileName: "source.mp4")

        #expect(savedURL == destinationURL)
        #expect(client.suggestedFileNames == ["source.mp4"])
        #expect(client.copiedFiles == [FileCopy(sourceURL: sourceURL, destinationURL: destinationURL)])
    }

    @Test("saveAs cancellation leaves the source untouched")
    func saveAsCancellationDoesNotCopy() throws {
        let sourceURL = URL(fileURLWithPath: "/tmp/source.mp4")
        let client = FakeExportedFileActionClient(destinationURL: nil)
        let service = ExportedFileWorkflowService(client: client)

        let savedURL = try service.saveAs(sourceURL)

        #expect(savedURL == nil)
        #expect(client.suggestedFileNames == ["source.mp4"])
        #expect(client.copiedFiles.isEmpty)
    }

    @Test("file actions delegate to the client")
    func fileActionsDelegateToClient() {
        let fileURL = URL(fileURLWithPath: "/tmp/export.gif")
        let client = FakeExportedFileActionClient(destinationURL: nil)
        let service = ExportedFileWorkflowService(client: client)

        service.copyFile(fileURL)
        service.copyPath(fileURL)
        service.copyText("diagnostic")
        service.revealInFinder(fileURL)
        service.openWithDefaultApp(fileURL)

        #expect(client.copiedFileURLs == [fileURL])
        #expect(client.copiedPathURLs == [fileURL])
        #expect(client.copiedTexts == ["diagnostic"])
        #expect(client.revealedURLs == [fileURL])
        #expect(client.openedURLs == [fileURL])
    }

    @Test("openWithApplication delegates when an app is selected")
    func openWithApplicationDelegatesWhenSelected() {
        let fileURL = URL(fileURLWithPath: "/tmp/export.mp4")
        let appURL = URL(fileURLWithPath: "/Applications/Preview.app")
        let client = FakeExportedFileActionClient(
            destinationURL: nil,
            applicationURL: appURL
        )
        let service = ExportedFileWorkflowService(client: client)

        let didOpen = service.openWithApplication(fileURL)

        #expect(didOpen)
        #expect(client.applicationSelectionURLs == [fileURL])
        #expect(
            client.openedWithApplications == [
                ApplicationOpen(fileURL: fileURL, applicationURL: appURL)
            ])
    }

    @Test("openWithApplication does nothing when app selection is canceled")
    func openWithApplicationDoesNothingWhenCanceled() {
        let fileURL = URL(fileURLWithPath: "/tmp/export.mp4")
        let client = FakeExportedFileActionClient(destinationURL: nil)
        let service = ExportedFileWorkflowService(client: client)

        let didOpen = service.openWithApplication(fileURL)

        #expect(!didOpen)
        #expect(client.applicationSelectionURLs == [fileURL])
        #expect(client.openedWithApplications.isEmpty)
    }

    @Test("chooseOutputDirectory returns the selected directory")
    func chooseOutputDirectoryReturnsSelectedDirectory() {
        let currentDirectory = URL(fileURLWithPath: "/tmp/current")
        let selectedDirectory = URL(fileURLWithPath: "/tmp/selected")
        let client = FakeExportedFileActionClient(
            destinationURL: nil,
            outputDirectoryURL: selectedDirectory
        )
        let service = ExportedFileWorkflowService(client: client)

        let outputDirectory = service.chooseOutputDirectory(currentDirectory: currentDirectory)

        #expect(outputDirectory == selectedDirectory)
        #expect(client.currentDirectoryURLs == [currentDirectory])
    }
}

private struct FileCopy: Equatable {
    let sourceURL: URL
    let destinationURL: URL
}

private struct ApplicationOpen: Equatable {
    let fileURL: URL
    let applicationURL: URL
}

@MainActor
private final class FakeExportedFileActionClient: ExportedFileActionClient {
    private let destinationURL: URL?
    private let outputDirectoryURL: URL?
    private let applicationURL: URL?
    private(set) var suggestedFileNames: [String] = []
    private(set) var currentDirectoryURLs: [URL] = []
    private(set) var applicationSelectionURLs: [URL] = []
    private(set) var copiedFiles: [FileCopy] = []
    private(set) var copiedFileURLs: [URL] = []
    private(set) var copiedPathURLs: [URL] = []
    private(set) var copiedTexts: [String] = []
    private(set) var revealedURLs: [URL] = []
    private(set) var openedURLs: [URL] = []
    private(set) var openedWithApplications: [ApplicationOpen] = []

    init(destinationURL: URL?, outputDirectoryURL: URL? = nil, applicationURL: URL? = nil) {
        self.destinationURL = destinationURL
        self.outputDirectoryURL = outputDirectoryURL
        self.applicationURL = applicationURL
    }

    func chooseSaveDestination(suggestedFileName: String) -> URL? {
        suggestedFileNames.append(suggestedFileName)
        return destinationURL
    }

    func chooseOutputDirectory(currentDirectory: URL) -> URL? {
        currentDirectoryURLs.append(currentDirectory)
        return outputDirectoryURL
    }

    func chooseApplicationForOpening(fileURL: URL) -> URL? {
        applicationSelectionURLs.append(fileURL)
        return applicationURL
    }

    func copyFile(from sourceURL: URL, to destinationURL: URL) {
        copiedFiles.append(FileCopy(sourceURL: sourceURL, destinationURL: destinationURL))
    }

    func copyFileToPasteboard(_ fileURL: URL) {
        copiedFileURLs.append(fileURL)
    }

    func copyPathToPasteboard(_ fileURL: URL) {
        copiedPathURLs.append(fileURL)
    }

    func copyTextToPasteboard(_ text: String) {
        copiedTexts.append(text)
    }

    func revealInFinder(_ fileURL: URL) {
        revealedURLs.append(fileURL)
    }

    func openWithDefaultApp(_ fileURL: URL) {
        openedURLs.append(fileURL)
    }

    func open(_ fileURL: URL, withApplicationAt applicationURL: URL) {
        openedWithApplications.append(ApplicationOpen(fileURL: fileURL, applicationURL: applicationURL))
    }
}
