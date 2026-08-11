import AVFoundation
import Foundation
import LuxelCore
import Testing

@testable import LuxelPresentation

@MainActor
@Suite("Luxel editor model")
struct LuxelEditorModelTests {
}

extension LuxelEditorModelTests {
    @Test("opening a keystroke sidecar enables preview controls and export options")
    func openingKeystrokeSidecarEnablesPreviewAndExportOptions() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("source.mp4")
        let timeline = try KeystrokeTimeline(events: [
            KeystrokeEvent(
                time: 0.25,
                kind: .keyDown,
                keyCode: 8,
                characters: "c",
                modifiers: [.command]
            )
        ])
        try JSONEncoder().encode(KeystrokeSidecarDocument(timeline: timeline)).write(
            to: KeystrokeSidecarDocument.sidecarURL(nextTo: sourceURL)
        )
        let model = makeModel()

        await model.open(fileURL: sourceURL, outputDirectory: directory)
        model.currentPlaybackTime = 0.5

        #expect(model.keystrokeTimeline == timeline)
        #expect(model.keystrokeOptions == .standard)
        #expect(model.activeKeystrokeChips.map(\.text) == ["⌘C"])
        let source = try #require(model.source)
        #expect(try model.makeExportRequest(source: source, format: .mp4).keystrokeOptions == .standard)
    }

    @Test("editor removal clears bundle keystrokes from disk and manifest")
    func editorRemovalClearsBundleKeystrokesAndManifest() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("screen.mov")
        FileManager.default.createFile(atPath: sourceURL.path, contents: Data())
        let manifest = try BundleManifest(
            primaryFileName: sourceURL.lastPathComponent,
            sidecars: [BundleSidecarManifest(kind: .keystrokes)]
        )
        let manifestURL = directory.appendingPathComponent(BundleManifest.fileName)
        let sidecarURL = directory.appendingPathComponent("keystrokes.json")
        try JSONEncoder().encode(manifest).write(to: manifestURL, options: .atomic)
        try JSONEncoder().encode(
            KeystrokeSidecarDocument(timeline: KeystrokeTimeline())
        ).write(to: sidecarURL, options: .atomic)
        let model = makeModel(fileSystem: LocalFileSystem())
        await model.open(fileURL: sourceURL, outputDirectory: directory)
        #expect(model.keystrokeTimeline != nil)

        model.removeKeystrokeData()

        let updatedManifest = try JSONDecoder().decode(
            BundleManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        #expect(updatedManifest.sidecar(for: .keystrokes) == nil)
        #expect(!FileManager.default.fileExists(atPath: sidecarURL.path))
        #expect(try KeystrokeSidecarFileLoader().load(nextTo: sourceURL) == nil)
        #expect(model.keystrokeTimeline == nil)
    }

    @Test("completed export shows progress panel actions")
    func completedExportShowsProgressPanelActions() async throws {
        let exportedURL = URL(fileURLWithPath: "/tmp/source Export.mp4")
        let model = makeModel(
            exporter: StubMediaExporter(exportedMedia: try exportedMedia(fileURL: exportedURL))
        )

        await model.open(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.startExport()

        while model.isExporting {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(model.showsExportProgressPanel)
        #expect(model.exportedURL == exportedURL)
        #expect(model.exportPanelTitle == "Export Complete")
        #expect(model.exportPanelSystemImage == "checkmark.circle")
        #expect(model.exportProgressValue == 1)
        #expect(!model.canRetryExport)
    }

    @Test("failed export can retry")
    func failedExportCanRetry() async throws {
        let model = makeModel()

        await model.open(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.status = .failed("Export failed")

        #expect(model.canRetryExport)
    }

    @Test("opening a recording clears stale export progress")
    func openingRecordingClearsStaleExportProgress() async throws {
        let model = makeModel()

        model.exportProgress = .completed(format: .mp4)
        await model.open(
            fileURL: URL(fileURLWithPath: "/tmp/next.mp4"), outputDirectory: URL(fileURLWithPath: "/tmp"))

        #expect(model.exportProgress == nil)
        #expect(!model.showsExportProgressPanel)
        #expect(model.status == .ready)
    }

    @Test("opening an alpha source uses alpha preview background")
    func openingAlphaSourceUsesAlphaPreviewBackground() async throws {
        let model = makeModel(metadataReader: StubMetadataReader(hasAlpha: true))

        await model.open(
            fileURL: URL(fileURLWithPath: "/tmp/alpha.mov"), outputDirectory: URL(fileURLWithPath: "/tmp")
        )

        #expect(model.usesAlphaPreviewBackground)
        #expect(model.sourceSummary.contains("alpha"))
    }

    @Test("opening an opaque source keeps standard preview background")
    func openingOpaqueSourceKeepsStandardPreviewBackground() async throws {
        let model = makeModel(metadataReader: StubMetadataReader(hasAlpha: false))

        await model.open(
            fileURL: URL(fileURLWithPath: "/tmp/opaque.mp4"),
            outputDirectory: URL(fileURLWithPath: "/tmp"))

        #expect(!model.usesAlphaPreviewBackground)
        #expect(!model.sourceSummary.contains("alpha"))
    }

    @Test("opening audio-only source selects m4a export")
    func openingAudioOnlySourceSelectsM4AExport() async throws {
        let exporter = SpyMediaExporter()
        let sourceURL = URL(fileURLWithPath: "/tmp/audio.m4a")
        let source = try SourceMedia.audioOnly(fileURL: sourceURL, duration: 12)
        let model = makeModel(
            metadataReader: StubMetadataReader(source: source),
            exporter: exporter
        )

        await model.open(fileURL: sourceURL, outputDirectory: URL(fileURLWithPath: "/tmp"))

        #expect(model.source?.isAudioOnly == true)
        #expect(model.supportedFormats == ExportFormat.audioOnlyFormats)
        #expect(model.format == .m4a)
        #expect(model.selectedFormats == [.m4a])
        #expect(model.includesAudio)
        #expect(model.canUseStudioVoice)
        #expect(!model.canToggleAudioInclusion)
        #expect(!model.canGrabFrame)
        #expect(!model.sourceSummary.contains("1x1"))

        model.setIncludesAudio(false)
        #expect(model.includesAudio)

        model.startExport()
        while model.isExporting {
            try await Task.sleep(for: .milliseconds(10))
        }

        let captured = await exporter.capturedExports()
        #expect(captured.first?.request.format == .m4a)
        #expect(captured.first?.request.outputShouldMute == false)
        #expect(captured.first?.request.shouldCrop == false)
    }

    @Test("pause playback stops playback without clearing the recording")
    func pausePlaybackStopsPlaybackWithoutClearingRecording() async throws {
        let model = makeModel()
        let sourceURL = URL(fileURLWithPath: "/tmp/source.mp4")

        await model.open(fileURL: sourceURL, outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.startPlayback()
        #expect(model.playbackRequested)

        model.pausePlayback()

        #expect(!model.playbackRequested)
        #expect(model.hasSource)
        #expect(model.player.currentItem != nil)
    }

    @Test("opening a new recording resets editor undo history")
    func openingNewRecordingResetsEditorUndoHistory() async throws {
        let model = makeModel()

        await model.open(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.setTrimStart(3)
        #expect(model.canUndoEditorChange)

        await model.open(
            fileURL: URL(fileURLWithPath: "/tmp/next.mp4"), outputDirectory: URL(fileURLWithPath: "/tmp"))

        #expect(!model.canUndoEditorChange)
        #expect(!model.canRedoEditorChange)

        model.undoEditorChange()

        #expect(model.trimStart == 0)
        #expect(model.source?.fileURL == URL(fileURLWithPath: "/tmp/next.mp4"))
    }

    @Test("opening recordings builds newest-first directory navigation")
    func openingRecordingsBuildsNewestFirstDirectoryNavigation() async throws {
        let model = makeModel()
        let directory = try temporaryDirectory()
        let olderURL = try makeRecordingFile(
            named: "older.mp4",
            in: directory,
            modificationDate: Date(timeIntervalSince1970: 2_100_000_000)
        )
        let latestURL = try makeRecordingFile(
            named: "latest.mp4",
            in: directory,
            modificationDate: Date(timeIntervalSince1970: 2_100_000_060)
        )
        _ = try makeRecordingFile(
            named: "latest-export.gif",
            in: directory,
            modificationDate: Date(timeIntervalSince1970: 2_100_000_120)
        )

        await model.open(fileURL: olderURL, outputDirectory: directory)

        #expect(
            model.recordingNavigationURLs == [
                latestURL.standardizedFileURL,
                olderURL.standardizedFileURL
            ])
        #expect(model.canNavigateToNewerRecording)
        #expect(!model.canNavigateToOlderRecording)

        await model.open(fileURL: latestURL, outputDirectory: directory)

        #expect(model.source?.fileURL == latestURL.standardizedFileURL)
        #expect(!model.canNavigateToNewerRecording)
        #expect(model.canNavigateToOlderRecording)

        await model.navigateToOlderRecording()

        #expect(model.source?.fileURL == olderURL.standardizedFileURL)
        #expect(model.canNavigateToNewerRecording)
        #expect(!model.canNavigateToOlderRecording)
    }

    @Test("opening selected nested recording keeps timestamp navigation order")
    func openingSelectedNestedRecordingKeepsTimestampNavigationOrder() async throws {
        let model = makeModel()
        let directory = try temporaryDirectory()
        let olderURL = try makeRecordingFile(
            named: "older.mp4",
            in: directory,
            modificationDate: Date(timeIntervalSince1970: 2_100_000_000)
        )
        let latestDirectory =
            directory
            .appending(path: "latest", directoryHint: .isDirectory)
            .standardizedFileURL
        try FileManager.default.createDirectory(
            at: latestDirectory,
            withIntermediateDirectories: true
        )
        let selectedURL = try makeRecordingFile(
            named: "screen.mov",
            in: latestDirectory,
            modificationDate: Date(timeIntervalSince1970: 2_100_000_060)
        )

        await model.open(fileURL: selectedURL, outputDirectory: directory)

        #expect(
            model.recordingNavigationURLs == [
                selectedURL.standardizedFileURL,
                olderURL.standardizedFileURL
            ])
        #expect(!model.canNavigateToNewerRecording)
        #expect(model.canNavigateToOlderRecording)
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

    @Test("import failure records non-fatal error")
    func importFailureRecordsNonFatalError() {
        let reporter = SpyErrorReporter()
        let model = makeModel(
            configuration: LuxelEditorModelTestConfiguration(errorReporter: reporter)
        )

        model.reportImportFailure(StubError.importFailed)

        #expect(
            reporter.records == [
                SpyErrorReporter.Record(context: "editor", description: "importFailed")
            ])
    }

    @Test("save original copies source without exporting")
    func saveOriginalCopiesSourceWithoutExporting() async throws {
        let fileSystem = SpyFileSystem()
        let model = makeModel(fileSystem: fileSystem)
        let sourceURL = URL(fileURLWithPath: "/tmp/source.mp4")

        await model.open(fileURL: sourceURL, outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.saveOriginal()

        while model.isExporting {
            try await Task.sleep(for: .milliseconds(10))
        }

        let expectedOutputURL = URL(fileURLWithPath: "/tmp/source Original.mp4")
        #expect(model.status == .saved(expectedOutputURL))
        #expect(fileSystem.createdDirectories.map(\.path) == ["/tmp"])
        #expect(
            fileSystem.copiedFiles == [
                CopiedFile(sourceURL: sourceURL, destinationURL: expectedOutputURL)
            ])
    }

    @Test("copy current frame sends frame to clipboard")
    func copyCurrentFrameSendsFrameToClipboard() async throws {
        let imageData = try frameImageData()
        let frameGrabber = SpyFrameGrabber(imageData: imageData)
        let destinationClient = SpyFrameGrabDestinationClient()
        let model = makeModel(frameGrabber: frameGrabber, frameGrabDestinationClient: destinationClient)
        let sourceURL = URL(fileURLWithPath: "/tmp/source.mp4")

        await model.open(fileURL: sourceURL, outputDirectory: URL(fileURLWithPath: "/tmp"))
        #expect(model.canGrabFrame)

        model.copyCurrentFrame()

        while model.isGrabbingFrame {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(destinationClient.copiedImages == [imageData])
        #expect(
            frameGrabber.requests == [
                try FrameGrabRequest(sourceFileURL: sourceURL, time: 0)
            ])
        #expect(model.status == .copiedFrame)
        #expect(model.statusMessage == "Copied frame")
    }

}
