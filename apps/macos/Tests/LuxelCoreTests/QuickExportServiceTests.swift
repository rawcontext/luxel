import Foundation
import LuxelCore
import Testing

@MainActor
@Suite("Quick export service")
struct QuickExportServiceTests {
    @Test("clipboard preset exports to recordings directory and copies result")
    func clipboardPresetExportsToRecordingsDirectoryAndCopiesResult() async throws {
        let metadataReader = SpyMetadataReader(source: try makeSource(width: 1920, height: 1080, frameRate: 60))
        let exporter = SpyMediaExporter(reportedProgress: [0.3, 0.8])
        let progress = ProgressRecorder()
        let client = FakeExportedFileActionClient()
        let service = QuickExportService(
            metadataReader: metadataReader,
            exportService: ExportService(exporter: exporter),
            fileWorkflowService: ExportedFileWorkflowService(client: client)
        )
        let recording = makeRecording()
        let recordingsDirectory = URL(fileURLWithPath: "/tmp/recordings")

        let result = try await service.runQuickExport(
            recording: recording,
            presetID: ExportPreset.quickGIFID,
            presets: ExportPreset.builtInDefaults,
            recordingsDirectory: recordingsDirectory
        ) { snapshot in
            await progress.append(snapshot)
        }

        let expectedOutputURL = URL(fileURLWithPath: "/tmp/recordings/Luxel Clip Quick GIF.gif")
        let capturedExport = await exporter.capturedExport()

        #expect(await metadataReader.requestedURLs() == [recording.fileURL])
        #expect(capturedExport?.outputFileURL == expectedOutputURL)
        #expect(capturedExport?.request.format == .gif)
        #expect(capturedExport?.request.pixelSize == (try PixelSize(width: 960, height: 540)))
        #expect(capturedExport?.request.frameRate == (try FrameRate(30)))
        #expect(result.exportedMedia.fileURL == expectedOutputURL)
        #expect(result.postAction == .copyToClipboard)
        #expect(client.copiedFileURLs == [expectedOutputURL])
        #expect(client.revealedURLs.isEmpty)
        #expect(await progress.snapshots() == [
            .preparing(format: .gif),
            .exporting(format: .gif, progress: 0),
            .exporting(format: .gif, progress: 0.3),
            .exporting(format: .gif, progress: 0.8),
            .completed(format: .gif)
        ])
    }

    @Test("folder preset exports to configured folder and reveals result")
    func folderPresetExportsToConfiguredFolderAndRevealsResult() async throws {
        let metadataReader = SpyMetadataReader(source: try makeSource())
        let exporter = SpyMediaExporter()
        let client = FakeExportedFileActionClient()
        let folderURL = URL(fileURLWithPath: "/tmp/custom")
        let preset = try ExportPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000501")!,
            name: "Folder MP4",
            format: .mp4,
            sizeRule: .original,
            frameRate: nil,
            destination: .folder(folderURL),
            postAction: .revealInFinder
        )
        let service = QuickExportService(
            metadataReader: metadataReader,
            exportService: ExportService(exporter: exporter),
            fileWorkflowService: ExportedFileWorkflowService(client: client)
        )

        let result = try await service.runQuickExport(
            recording: makeRecording(),
            presetID: preset.id,
            presets: [preset],
            recordingsDirectory: URL(fileURLWithPath: "/tmp/recordings")
        )

        let expectedOutputURL = URL(fileURLWithPath: "/tmp/custom/Luxel Clip Folder MP4.mp4")
        #expect(await exporter.capturedExport()?.outputFileURL == expectedOutputURL)
        #expect(result.exportedMedia.fileURL == expectedOutputURL)
        #expect(result.postAction == .revealInFinder)
        #expect(client.revealedURLs == [expectedOutputURL])
        #expect(client.copiedFileURLs.isEmpty)
    }

    @Test("recordings directory bookmark resolves quick export destination")
    func recordingsDirectoryBookmarkResolvesQuickExportDestination() async throws {
        let metadataReader = SpyMetadataReader(source: try makeSource())
        let exporter = SpyMediaExporter()
        let access = QuickExportScopedAccess()
        let bookmark = BookmarkedDirectory(
            url: URL(fileURLWithPath: "/tmp/stale-recordings"),
            bookmarkData: Data([0x10])
        )
        let directoryAccessService = BookmarkedDirectoryAccessService(
            resolver: QuickExportBookmarkResolver(
                resolution: BookmarkedDirectoryResolution(
                    url: URL(fileURLWithPath: "/tmp/resolved-recordings"),
                    bookmarkData: bookmark.bookmarkData,
                    isStale: false
                )
            ),
            access: access
        )
        let service = QuickExportService(
            metadataReader: metadataReader,
            exportService: ExportService(exporter: exporter),
            fileWorkflowService: ExportedFileWorkflowService(client: FakeExportedFileActionClient()),
            directoryAccessService: directoryAccessService
        )

        let result = try await service.runQuickExport(
            recording: makeRecording(),
            presetID: ExportPreset.quickGIFID,
            presets: ExportPreset.builtInDefaults,
            recordingsDirectory: bookmark.url,
            recordingsDirectoryBookmark: bookmark
        )

        let expectedOutputURL = URL(fileURLWithPath: "/tmp/resolved-recordings/Luxel Clip Quick GIF.gif")
        #expect(await exporter.capturedExport()?.outputFileURL == expectedOutputURL)
        #expect(result.exportedMedia.fileURL == expectedOutputURL)
        #expect(access.startedURLs == [URL(fileURLWithPath: "/tmp/resolved-recordings")])
        #expect(access.stoppedURLs == [URL(fileURLWithPath: "/tmp/resolved-recordings")])
        #expect(access.activeURLs.isEmpty)
    }

    @Test("notify post action delegates to user notifier")
    func notifyPostActionDelegatesToUserNotifier() async throws {
        let metadataReader = SpyMetadataReader(source: try makeSource())
        let exporter = SpyMediaExporter()
        let client = FakeExportedFileActionClient()
        let notifier = SpyUserNotifier()
        let preset = try ExportPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000502")!,
            name: "Notify MP4",
            format: .mp4,
            sizeRule: .original,
            frameRate: nil,
            destination: .recordingsDirectory,
            postAction: .notifyWithThumbnail
        )
        let service = QuickExportService(
            metadataReader: metadataReader,
            exportService: ExportService(exporter: exporter),
            fileWorkflowService: ExportedFileWorkflowService(client: client),
            userNotifier: notifier
        )

        let result = try await service.runQuickExport(
            recording: makeRecording(),
            presetID: preset.id,
            presets: [preset],
            recordingsDirectory: URL(fileURLWithPath: "/tmp/recordings")
        )

        let expectedOutputURL = URL(fileURLWithPath: "/tmp/recordings/Luxel Clip Notify MP4.mp4")
        #expect(result.postAction == .notifyWithThumbnail)
        #expect(await notifier.notifications() == [
            ExportNotification(fileURL: expectedOutputURL, presetName: "Notify MP4")
        ])
    }

    @Test("missing preset fails before reading metadata or exporting")
    func missingPresetFailsBeforeReadingMetadataOrExporting() async throws {
        let metadataReader = SpyMetadataReader(source: try makeSource())
        let exporter = SpyMediaExporter()
        let service = QuickExportService(
            metadataReader: metadataReader,
            exportService: ExportService(exporter: exporter),
            fileWorkflowService: ExportedFileWorkflowService(client: FakeExportedFileActionClient())
        )
        let presetID = UUID(uuidString: "00000000-0000-0000-0000-000000000599")!

        await #expect(throws: QuickExportError.presetNotFound(presetID)) {
            _ = try await service.runQuickExport(
                recording: makeRecording(),
                presetID: presetID,
                presets: ExportPreset.builtInDefaults,
                recordingsDirectory: URL(fileURLWithPath: "/tmp/recordings")
            )
        }

        #expect(await metadataReader.requestedURLs().isEmpty)
        #expect(await exporter.capturedExport() == nil)
    }

    @Test("notify post action requires a notifier")
    func notifyPostActionRequiresNotifier() async throws {
        let preset = try ExportPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000503")!,
            name: "Notify MP4",
            format: .mp4,
            sizeRule: .original,
            frameRate: nil,
            destination: .recordingsDirectory,
            postAction: .notifyWithThumbnail
        )
        let service = QuickExportService(
            metadataReader: SpyMetadataReader(source: try makeSource()),
            exportService: ExportService(exporter: SpyMediaExporter()),
            fileWorkflowService: ExportedFileWorkflowService(client: FakeExportedFileActionClient())
        )

        await #expect(throws: QuickExportError.notifierUnavailable) {
            _ = try await service.runQuickExport(
                recording: makeRecording(),
                presetID: preset.id,
                presets: [preset],
                recordingsDirectory: URL(fileURLWithPath: "/tmp/recordings")
            )
        }
    }

    private func makeRecording() -> PastRecording {
        PastRecording(
            fileURL: URL(fileURLWithPath: "/tmp/Luxel Clip.mp4"),
            name: "Luxel Clip",
            date: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private func makeSource(
        width: Int = 1280,
        height: Int = 720,
        frameRate: Int = 30,
        hasAudio: Bool = true
    ) throws -> SourceMedia {
        try SourceMedia(
            fileURL: URL(fileURLWithPath: "/tmp/Luxel Clip.mp4"),
            duration: 10,
            pixelSize: PixelSize(width: width, height: height),
            nominalFrameRate: FrameRate(frameRate),
            hasAudio: hasAudio
        )
    }
}

private actor SpyMetadataReader: MediaMetadataReader {
    private let source: SourceMedia
    private var capturedURLs: [URL] = []

    init(source: SourceMedia) {
        self.source = source
    }

    func readSourceMedia(at fileURL: URL) async throws -> SourceMedia {
        capturedURLs.append(fileURL)
        return source
    }

    func requestedURLs() -> [URL] {
        capturedURLs
    }
}

private actor SpyMediaExporter: MediaExporter {
    private let reportedProgress: [Double]
    private var captured: (request: ExportRequest, outputFileURL: URL)?

    init(reportedProgress: [Double] = []) {
        self.reportedProgress = reportedProgress
    }

    func export(_ request: ExportRequest, to outputFileURL: URL) async throws -> ExportedMedia {
        try await export(request, to: outputFileURL, progress: nil)
    }

    func export(
        _ request: ExportRequest,
        to outputFileURL: URL,
        progress: MediaExportProgressHandler?
    ) async throws -> ExportedMedia {
        captured = (request, outputFileURL)
        for value in reportedProgress {
            await progress?(value)
        }

        return try ExportedMedia(
            fileURL: outputFileURL,
            format: request.format,
            pixelSize: request.outputPixelSize,
            shouldMute: request.outputShouldMute
        )
    }

    func capturedExport() -> (request: ExportRequest, outputFileURL: URL)? {
        captured
    }
}

private actor ProgressRecorder {
    private var captured: [ExportProgressSnapshot] = []

    func append(_ snapshot: ExportProgressSnapshot) {
        captured.append(snapshot)
    }

    func snapshots() -> [ExportProgressSnapshot] {
        captured
    }
}

private struct ExportNotification: Equatable, Sendable {
    let fileURL: URL
    let presetName: String
}

private actor SpyUserNotifier: UserNotifier {
    private var captured: [ExportNotification] = []

    func notifyExportCompleted(fileURL: URL, presetName: String) async {
        captured.append(ExportNotification(fileURL: fileURL, presetName: presetName))
    }

    func notifications() -> [ExportNotification] {
        captured
    }
}

@MainActor
private final class FakeExportedFileActionClient: ExportedFileActionClient {
    private(set) var copiedFileURLs: [URL] = []
    private(set) var revealedURLs: [URL] = []

    func chooseSaveDestination(suggestedFileName: String) -> URL? {
        nil
    }

    func chooseOutputDirectory(currentDirectory: URL) -> URL? {
        nil
    }

    func chooseApplicationForOpening(fileURL: URL) -> URL? {
        nil
    }

    func copyFile(from sourceURL: URL, to destinationURL: URL) {}

    func copyFileToPasteboard(_ fileURL: URL) {
        copiedFileURLs.append(fileURL)
    }

    func copyPathToPasteboard(_ fileURL: URL) {}

    func copyTextToPasteboard(_ text: String) {}

    func revealInFinder(_ fileURL: URL) {
        revealedURLs.append(fileURL)
    }

    func openWithDefaultApp(_ fileURL: URL) {}

    func open(_ fileURL: URL, withApplicationAt applicationURL: URL) {}
}

private struct QuickExportBookmarkResolver: BookmarkedDirectoryResolver {
    let resolution: BookmarkedDirectoryResolution

    func resolve(_ directory: BookmarkedDirectory) throws -> BookmarkedDirectoryResolution {
        resolution
    }
}

private final class QuickExportScopedAccess: SecurityScopedResourceAccess, @unchecked Sendable {
    private(set) var startedURLs: [URL] = []
    private(set) var stoppedURLs: [URL] = []
    private(set) var activeURLs: [URL] = []

    func startAccessing(_ url: URL) -> Bool {
        startedURLs.append(url)
        activeURLs.append(url)
        return true
    }

    func stopAccessing(_ url: URL) {
        stoppedURLs.append(url)
        activeURLs.removeAll { $0 == url }
    }
}
