import Foundation
import LuxelCore
import Testing
@testable import LuxelPresentation

@MainActor
@Suite("Luxel editor model")
struct LuxelEditorModelTests {
    @Test("completed export shows progress panel actions")
    func completedExportShowsProgressPanelActions() async throws {
        let exportedURL = URL(fileURLWithPath: "/tmp/source Export.mp4")
        let model = makeModel(
            exporter: StubMediaExporter(exportedMedia: try exportedMedia(fileURL: exportedURL))
        )

        await model.open(fileURL: URL(fileURLWithPath: "/tmp/source.mp4"), outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.startExport()

        while model.isExporting {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(model.showsExportProgressPanel)
        #expect(model.exportedURL == exportedURL)
        #expect(model.exportPanelTitle == "Export Complete")
        #expect(model.exportPanelSystemImage == "checkmark.circle")
        #expect(model.exportProgressValue == 1)
        #expect(model.canRetryExport)
    }

    @Test("opening a recording clears stale export progress")
    func openingRecordingClearsStaleExportProgress() async throws {
        let model = makeModel()

        model.exportProgress = .completed(format: .mp4)
        await model.open(fileURL: URL(fileURLWithPath: "/tmp/next.mp4"), outputDirectory: URL(fileURLWithPath: "/tmp"))

        #expect(model.exportProgress == nil)
        #expect(!model.showsExportProgressPanel)
        #expect(model.status == .ready)
    }

    @Test("import failure clears stale export progress")
    func importFailureClearsStaleExportProgress() {
        let model = makeModel()

        model.exportProgress = .completed(format: .mp4)
        model.reportImportFailure(StubError.importFailed)

        #expect(model.exportProgress == nil)
        #expect(!model.showsExportProgressPanel)
        #expect(!model.hasSource)
    }

    private func makeModel(
        exporter: any MediaExporter = StubMediaExporter()
    ) -> LuxelEditorModel {
        LuxelEditorModel(
            metadataReader: StubMetadataReader(),
            exportService: ExportService(
                exporter: exporter,
                fileSystem: StubFileSystem()
            ),
            fileWorkflowService: ExportedFileWorkflowService(
                client: StubExportedFileActionClient()
            )
        )
    }

    private func exportedMedia(fileURL: URL) throws -> ExportedMedia {
        try ExportedMedia(
            fileURL: fileURL,
            format: .mp4,
            pixelSize: PixelSize(width: 1280, height: 720),
            shouldMute: false
        )
    }
}

private enum StubError: Error {
    case importFailed
}

private struct StubMetadataReader: MediaMetadataReader {
    func readSourceMedia(at fileURL: URL) async throws -> SourceMedia {
        try SourceMedia(
            fileURL: fileURL,
            duration: 12,
            pixelSize: PixelSize(width: 1280, height: 720),
            nominalFrameRate: FrameRate(30),
            hasAudio: true
        )
    }
}

private struct StubMediaExporter: MediaExporter {
    let exportedMedia: ExportedMedia?

    init(exportedMedia: ExportedMedia? = nil) {
        self.exportedMedia = exportedMedia
    }

    func export(_ request: ExportRequest, to outputFileURL: URL) async throws -> ExportedMedia {
        if let exportedMedia {
            return exportedMedia
        }

        return ExportedMedia(
            fileURL: outputFileURL,
            format: request.format,
            pixelSize: try request.outputPixelSize,
            shouldMute: request.outputShouldMute
        )
    }
}

private struct StubFileSystem: FileSystem {
    func fileExists(at url: URL) -> Bool {
        true
    }

    func removeFile(at url: URL) throws {}
}

@MainActor
private final class StubExportedFileActionClient: ExportedFileActionClient {
    func chooseSaveDestination(suggestedFileName: String) -> URL? {
        nil
    }

    func chooseOutputDirectory(currentDirectory: URL) -> URL? {
        nil
    }

    func chooseApplicationForOpening(fileURL: URL) -> URL? {
        nil
    }

    func copyFile(from sourceURL: URL, to destinationURL: URL) throws {}

    func copyFileToPasteboard(_ fileURL: URL) {}

    func copyPathToPasteboard(_ fileURL: URL) {}

    func copyTextToPasteboard(_ text: String) {}

    func revealInFinder(_ fileURL: URL) {}

    func openWithDefaultApp(_ fileURL: URL) {}

    func open(_ fileURL: URL, withApplicationAt applicationURL: URL) {}
}
