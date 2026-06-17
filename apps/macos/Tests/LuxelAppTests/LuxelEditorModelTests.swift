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
        #expect(!model.canRetryExport)
    }

    @Test("failed export can retry")
    func failedExportCanRetry() async throws {
        let model = makeModel()

        await model.open(fileURL: URL(fileURLWithPath: "/tmp/source.mp4"), outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.status = .failed("Export failed")

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

    @Test("opening an alpha source uses alpha preview background")
    func openingAlphaSourceUsesAlphaPreviewBackground() async throws {
        let model = makeModel(metadataReader: StubMetadataReader(hasAlpha: true))

        await model.open(fileURL: URL(fileURLWithPath: "/tmp/alpha.mov"), outputDirectory: URL(fileURLWithPath: "/tmp"))

        #expect(model.usesAlphaPreviewBackground)
        #expect(model.sourceSummary.contains("alpha"))
    }

    @Test("opening an opaque source keeps standard preview background")
    func openingOpaqueSourceKeepsStandardPreviewBackground() async throws {
        let model = makeModel(metadataReader: StubMetadataReader(hasAlpha: false))

        await model.open(fileURL: URL(fileURLWithPath: "/tmp/opaque.mp4"), outputDirectory: URL(fileURLWithPath: "/tmp"))

        #expect(!model.usesAlphaPreviewBackground)
        #expect(!model.sourceSummary.contains("alpha"))
    }

    @Test("opening a new recording resets editor undo history")
    func openingNewRecordingResetsEditorUndoHistory() async throws {
        let model = makeModel()

        await model.open(fileURL: URL(fileURLWithPath: "/tmp/source.mp4"), outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.setTrimStart(3)
        #expect(model.canUndoEditorChange)

        await model.open(fileURL: URL(fileURLWithPath: "/tmp/next.mp4"), outputDirectory: URL(fileURLWithPath: "/tmp"))

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

        #expect(model.recordingNavigationURLs == [
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
        let model = makeModel(errorReporter: reporter)

        model.reportImportFailure(StubError.importFailed)

        #expect(reporter.records == [
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
        #expect(fileSystem.copiedFiles == [
            CopiedFile(sourceURL: sourceURL, destinationURL: expectedOutputURL)
        ])
    }

    @Test("copy current frame sends frame to clipboard")
    func copyCurrentFrameSendsFrameToClipboard() async throws {
        let imageData = try frameImageData()
        let frameGrabber = SpyFrameGrabber(imageData: imageData)
        let destinationClient = SpyScreenshotDestinationClient()
        let model = makeModel(frameGrabber: frameGrabber, screenshotDestinationClient: destinationClient)
        let sourceURL = URL(fileURLWithPath: "/tmp/source.mp4")

        await model.open(fileURL: sourceURL, outputDirectory: URL(fileURLWithPath: "/tmp"))
        #expect(model.canGrabFrame)

        model.copyCurrentFrame()

        while model.isGrabbingFrame {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(destinationClient.copiedImages == [imageData])
        #expect(frameGrabber.requests == [
            try FrameGrabRequest(sourceFileURL: sourceURL, time: 0, format: .png)
        ])
        #expect(model.status == .copiedFrame)
        #expect(model.statusMessage == "Copied frame")
    }

    @Test("save current frame asks for destination and writes selected file")
    func saveCurrentFrameAsksForDestinationAndWritesSelectedFile() async throws {
        let imageData = try frameImageData()
        let frameGrabber = SpyFrameGrabber(imageData: imageData)
        let fileWriter = SpyScreenshotFileWriter()
        let destinationURL = URL(fileURLWithPath: "/tmp/source frame.png")
        let fileActionClient = StubExportedFileActionClient(saveDestination: destinationURL)
        let model = makeModel(
            fileActionClient: fileActionClient,
            frameGrabber: frameGrabber,
            screenshotFileWriter: fileWriter
        )
        let sourceURL = URL(fileURLWithPath: "/tmp/source.mp4")

        await model.open(fileURL: sourceURL, outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.saveCurrentFrameAs()

        while model.isGrabbingFrame {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(fileActionClient.requestedSaveNames == ["source (frame 0.00.0).png"])
        #expect(fileWriter.writes == [
            SpyScreenshotFileWriter.Write(imageData: imageData, fileURL: destinationURL)
        ])
        #expect(frameGrabber.requests == [
            try FrameGrabRequest(sourceFileURL: sourceURL, time: 0, format: .png)
        ])
        #expect(model.status == .savedFrame(destinationURL))
        #expect(model.statusMessage == "Saved source frame.png")
    }

    @Test("discard recording trashes source and clears editor")
    func discardRecordingTrashesSourceAndClearsEditor() async throws {
        let fileSystem = SpyFileSystem()
        let sourceURL = URL(fileURLWithPath: "/tmp/source.mp4")
        var discardedURLs: [URL] = []
        let model = makeModel(fileSystem: fileSystem)
        model.configureDiscard(confirmDiscard: false) { fileURL in
            discardedURLs.append(fileURL)
        }

        await model.open(fileURL: sourceURL, outputDirectory: URL(fileURLWithPath: "/tmp"))
        let didDiscard = model.discardRecording()

        #expect(didDiscard)
        #expect(fileSystem.trashedFiles == [sourceURL])
        #expect(discardedURLs == [sourceURL])
        #expect(!model.hasSource)
        #expect(!model.canDiscard)
        #expect(model.status == .discarded("source.mp4"))
        #expect(model.statusMessage == "Discarded source.mp4")
    }

    @Test("discard recording keeps source when trash fails")
    func discardRecordingKeepsSourceWhenTrashFails() async throws {
        let fileSystem = SpyFileSystem(trashError: StubError.trashFailed)
        let sourceURL = URL(fileURLWithPath: "/tmp/source.mp4")
        var discardedURLs: [URL] = []
        let model = makeModel(fileSystem: fileSystem)
        model.configureDiscard(confirmDiscard: false) { fileURL in
            discardedURLs.append(fileURL)
        }

        await model.open(fileURL: sourceURL, outputDirectory: URL(fileURLWithPath: "/tmp"))
        let didDiscard = model.discardRecording()

        #expect(!didDiscard)
        #expect(fileSystem.trashedFiles == [sourceURL])
        #expect(discardedURLs.isEmpty)
        #expect(model.hasSource)

        if case .failed = model.status {
        } else {
            Issue.record("Expected discard failure status")
        }
    }

    @Test("discard confirmation setting emits changes")
    func discardConfirmationSettingEmitsChanges() {
        var capturedSettings: [Bool] = []
        let model = makeModel()
        model.configureDiscard(
            confirmDiscard: true,
            onConfirmDiscardChange: { confirmDiscard in
                capturedSettings.append(confirmDiscard)
            }
        )

        model.setConfirmDiscard(false)
        model.setConfirmDiscard(false)
        model.setConfirmDiscard(true)

        #expect(model.confirmDiscard)
        #expect(capturedSettings == [false, true])
    }

    @Test("refreshing export estimate builds request from current editor state")
    func refreshingExportEstimateBuildsRequestFromCurrentEditorState() async throws {
        let estimator = SpyExportSizeEstimator()
        let model = makeModel(exportSizeEstimator: estimator)

        await model.open(fileURL: URL(fileURLWithPath: "/tmp/source.mp4"), outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.setFormat(.hevc)
        model.setTrimStart(2)
        model.setTrimEnd(8)
        model.setOutputWidth(640)
        model.setOutputHeight(360)
        model.setFrameRate(24)
        model.setPlaybackSpeed(2)
        model.setQuality(.high)
        model.setIncludesAudio(false)
        await model.refreshExportEstimate()

        let expectedEstimate = try ExportEstimate(bytes: 1_500_000, confidence: .modeled)
        let expectedRange = try TimeRange(start: 2, end: 8)
        let expectedPixelSize = try PixelSize(width: 640, height: 360)
        let expectedFrameRate = try FrameRate(24)
        let captured = await estimator.request()

        #expect(model.exportEstimate == expectedEstimate)
        #expect(model.exportEstimateSummary == "~ 1.5 MB")
        #expect(captured?.format == .hevc)
        #expect(captured?.timeRange == expectedRange)
        #expect(captured?.pixelSize == expectedPixelSize)
        #expect(captured?.frameRate == expectedFrameRate)
        #expect(captured?.speed == (try PlaybackSpeed(2)))
        #expect(captured?.quality == .high)
        #expect(captured?.outputShouldMute == true)
    }

    @Test("refreshing GIF export estimate includes GIF options")
    func refreshingGIFExportEstimateIncludesGIFOptions() async throws {
        let estimator = SpyExportSizeEstimator()
        let model = makeModel(exportSizeEstimator: estimator)

        await model.open(fileURL: URL(fileURLWithPath: "/tmp/source.mp4"), outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.setFormat(.gif)
        model.setQuality(.compact)
        model.setGIFLoopModeKind(.bounce)
        model.setGIFDithering(.diffusion)
        await model.refreshExportEstimate()

        let captured = await estimator.request()
        let expectedOptions = try GIFRenderOptions(
            quality: .compact,
            loopMode: .bounce,
            dithering: .diffusion
        )

        #expect(captured?.format == .gif)
        #expect(captured?.gifOptions == expectedOptions)
    }

    @Test("refreshing APNG export estimate includes loop options")
    func refreshingAPNGExportEstimateIncludesLoopOptions() async throws {
        let estimator = SpyExportSizeEstimator()
        let model = makeModel(exportSizeEstimator: estimator)

        await model.open(fileURL: URL(fileURLWithPath: "/tmp/source.mp4"), outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.setFormat(.apng)
        model.setGIFLoopModeKind(.bounce)
        await model.refreshExportEstimate()

        let captured = await estimator.request()
        let expectedOptions = try GIFRenderOptions(loopMode: .bounce)

        #expect(captured?.format == .apng)
        #expect(captured?.gifOptions == expectedOptions)
    }

    @Test("format changes clamp unavailable quality")
    func formatChangesClampUnavailableQuality() {
        let model = makeModel()

        model.setQuality(.high)
        #expect(model.quality == .high)
        #expect(model.availableQualities == [.compact, .balanced, .high])

        model.setFormat(.apng)
        #expect(model.quality == .lossless)
        #expect(model.availableQualities == [.lossless])
        #expect(!model.canChooseQuality)

        model.setQuality(.balanced)
        #expect(model.quality == .lossless)
    }

    @Test("format selection keeps at least one format")
    func formatSelectionKeepsAtLeastOneFormat() async throws {
        let model = makeModel()

        await model.open(fileURL: URL(fileURLWithPath: "/tmp/source.mp4"), outputDirectory: URL(fileURLWithPath: "/tmp"))

        model.setFormatSelection(.mp4, isSelected: false)
        #expect(model.selectedFormats == [.mp4])
        #expect(model.selectedFormatSummary == "MP4 (H264)")

        model.setFormatSelection(.gif, isSelected: true)
        #expect(model.selectedFormats == [.mp4, .gif])
        #expect(model.format == .gif)
        #expect(model.selectedFormatSummary == "2 Formats")

        model.setFormatSelection(.gif, isSelected: false)
        #expect(model.selectedFormats == [.mp4])
        #expect(model.format == .mp4)
    }

    @Test("codec availability gates editor formats")
    func codecAvailabilityGatesEditorFormats() async throws {
        let defaultModel = makeModel()

        #expect(defaultModel.supportedFormats == [.mp4, .hevc, .gif, .apng])
        defaultModel.setFormat(.webm)
        #expect(defaultModel.format == .mp4)
        #expect(defaultModel.selectedFormats == [.mp4])
        defaultModel.setFormatSelection(.webm, isSelected: true)
        #expect(defaultModel.selectedFormats == [.mp4])

        let codecModel = makeModel(
            codecAvailability: try CodecAvailability(registeredExternalFormats: [.webm])
        )

        #expect(codecModel.supportedFormats == [.mp4, .hevc, .gif, .apng, .webm])
        codecModel.setFormatSelection(.webm, isSelected: true)
        #expect(codecModel.format == .webm)
        #expect(codecModel.selectedFormats == [.mp4, .webm])
    }

    @Test("export memory seeds controls when opening and changing formats")
    func exportMemorySeedsControlsWhenOpeningAndChangingFormats() async throws {
        let gifOptions = try GIFRenderOptions(
            quality: .compact,
            loopMode: .counted(4),
            dithering: .ordered
        )
        let memory: [ExportFormat: ExportMemory] = [
            .mp4: try ExportMemory(
                sizePreset: .percent50,
                frameRate: FrameRate(24),
                quality: .high
            ),
            .gif: try ExportMemory(
                sizePreset: .percent25,
                frameRate: FrameRate(12),
                quality: .compact,
                gifOptions: gifOptions
            ),
            .apng: try ExportMemory(
                sizePreset: .percent75,
                frameRate: FrameRate(120),
                quality: .balanced,
                gifOptions: GIFRenderOptions(loopMode: .none)
            )
        ]
        let model = makeModel(exportMemory: memory)

        await model.open(fileURL: URL(fileURLWithPath: "/tmp/source.mp4"), outputDirectory: URL(fileURLWithPath: "/tmp"))

        #expect(model.sizePreset == .percent50)
        #expect(model.outputWidth == 640)
        #expect(model.outputHeight == 360)
        #expect(model.frameRate == 24)
        #expect(model.quality == .high)

        model.setFormat(.gif)

        #expect(model.sizePreset == .percent25)
        #expect(model.outputWidth == 320)
        #expect(model.outputHeight == 180)
        #expect(model.frameRate == 12)
        #expect(model.quality == .compact)
        #expect(model.gifLoopModeKind == .count)
        #expect(model.gifLoopCount == 4)
        #expect(model.gifDithering == .ordered)
        #expect(model.gifLoopMode == .count(4))

        model.setFormat(.apng)

        #expect(model.sizePreset == .percent75)
        #expect(model.outputWidth == 960)
        #expect(model.outputHeight == 540)
        #expect(model.frameRate == 60)
        #expect(model.quality == .lossless)
        #expect(model.gifLoopModeKind == .none)
        #expect(model.gifLoopMode == .none)
    }

    @Test("format change with memory is one undo step")
    func formatChangeWithMemoryIsOneUndoStep() async throws {
        let memory: [ExportFormat: ExportMemory] = [
            .hevc: try ExportMemory(
                sizePreset: .percent50,
                frameRate: FrameRate(24),
                quality: .high
            )
        ]
        let model = makeModel(exportMemory: memory)

        await model.open(fileURL: URL(fileURLWithPath: "/tmp/source.mp4"), outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.setFormat(.hevc)

        #expect(model.format == .hevc)
        #expect(model.selectedFormats == [.hevc])
        #expect(model.sizePreset == .percent50)
        #expect(model.outputWidth == 640)
        #expect(model.frameRate == 24)
        #expect(model.quality == .high)

        model.undoEditorChange()

        #expect(model.format == .mp4)
        #expect(model.selectedFormats == [.mp4])
        #expect(model.sizePreset == .original)
        #expect(model.outputWidth == 1280)
        #expect(model.frameRate == 60)
        #expect(model.quality == .balanced)
        #expect(!model.canUndoEditorChange)
        #expect(model.canRedoEditorChange)

        model.redoEditorChange()

        #expect(model.format == .hevc)
        #expect(model.sizePreset == .percent50)
        #expect(model.outputWidth == 640)
        #expect(model.frameRate == 24)
        #expect(model.quality == .high)
    }

    @Test("editor undo redo restores draft options")
    func editorUndoRedoRestoresDraftOptions() async throws {
        let model = makeModel()

        await model.open(fileURL: URL(fileURLWithPath: "/tmp/source.mp4"), outputDirectory: URL(fileURLWithPath: "/tmp"))
        #expect(!model.canUndoEditorChange)
        #expect(!model.canRedoEditorChange)

        model.setSizePreset(.percent50)
        model.setIncludesAudio(false)
        model.setShouldCrop(false)

        #expect(model.sizePreset == .percent50)
        #expect(model.outputWidth == 640)
        #expect(!model.includesAudio)
        #expect(!model.shouldCrop)

        model.undoEditorChange()

        #expect(model.sizePreset == .percent50)
        #expect(model.outputWidth == 640)
        #expect(!model.includesAudio)
        #expect(model.shouldCrop)

        model.undoEditorChange()

        #expect(model.sizePreset == .percent50)
        #expect(model.outputWidth == 640)
        #expect(model.includesAudio)
        #expect(model.shouldCrop)

        model.redoEditorChange()

        #expect(!model.includesAudio)
        #expect(model.shouldCrop)
        #expect(model.canUndoEditorChange)
    }

    @Test("playback speed participates in undo and export requests")
    func playbackSpeedParticipatesInUndoAndExportRequests() async throws {
        let exporter = SpyMediaExporter()
        let model = makeModel(exporter: exporter)

        await model.open(fileURL: URL(fileURLWithPath: "/tmp/source.mp4"), outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.setPlaybackSpeed(2)

        #expect(model.playbackSpeed == (try PlaybackSpeed(2)))
        #expect(model.outputDurationSummary == "0:06")

        model.undoEditorChange()
        #expect(model.playbackSpeed == .normal)
        #expect(model.outputDurationSummary == "0:12")

        model.redoEditorChange()
        #expect(model.playbackSpeed == (try PlaybackSpeed(2)))

        model.startExport()
        while model.isExporting {
            try await Task.sleep(for: .milliseconds(10))
        }

        let captured = await exporter.capturedExports()
        #expect(captured.first?.request.speed == (try PlaybackSpeed(2)))
    }

    @Test("audio mix participates in undo and export requests")
    func audioMixParticipatesInUndoAndExportRequests() async throws {
        let exporter = SpyMediaExporter()
        let model = makeModel(exporter: exporter)

        await model.open(fileURL: URL(fileURLWithPath: "/tmp/source.mp4"), outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.setAudioVolume(0.35)
        model.setNormalizeAudio(true)

        #expect(model.audioVolume == 0.35)
        #expect(model.audioVolumePercentSummary == "35%")
        #expect(model.normalizeAudio)

        model.undoEditorChange()

        #expect(!model.normalizeAudio)
        #expect(model.audioVolume == 0.35)

        model.redoEditorChange()

        #expect(model.normalizeAudio)

        model.startExport()
        while model.isExporting {
            try await Task.sleep(for: .milliseconds(10))
        }

        let expectedAudioMix = AudioMixPlan(
            tracks: [AudioTrackMix(kind: .system, volume: 0.35)],
            normalizePeak: true
        )
        let captured = await exporter.capturedExports()
        #expect(captured.first?.request.audioMix == expectedAudioMix)
    }

    @Test("audio mix controls apply to preview playback")
    func audioMixControlsApplyToPreviewPlayback() async throws {
        let model = makeModel()

        await model.open(fileURL: try fixtureURL("input@2x.mp4"), outputDirectory: URL(fileURLWithPath: "/tmp"))

        #expect(!model.player.isMuted)
        #expect(model.player.currentItem?.audioMix == nil)

        model.setAudioVolume(0.25)

        let audioMix = try await waitForPreviewAudioMix(model)
        let inputParameters = try #require(audioMix.inputParameters.first)
        let audioVolumeRamp = try #require(previewAudioVolumeRamp(for: inputParameters))

        #expect(isApproximately(Double(audioVolumeRamp.start), 0.25))
        #expect(isApproximately(Double(audioVolumeRamp.end), 0.25))

        model.setIncludesAudio(false)

        #expect(model.player.isMuted)
        #expect(model.player.currentItem?.audioMix == nil)
    }

    @Test("normalize audio applies analyzed gain to preview playback")
    func normalizeAudioAppliesAnalyzedGainToPreviewPlayback() async throws {
        let analyzer = SpyAudioPeakAnalyzer(peaks: [.system: 0.5])
        let model = makeModel(audioPeakAnalyzer: analyzer)
        let sourceURL = try fixtureURL("input@2x.mp4")

        await model.open(fileURL: sourceURL, outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.setTrimStart(1)
        model.setTrimEnd(4)
        model.setNormalizeAudio(true)

        let audioMix = try await waitForPreviewAudioMix(model)
        let inputParameters = try #require(audioMix.inputParameters.first)
        let audioVolumeRamp = try #require(previewAudioVolumeRamp(for: inputParameters))
        let expectedGain = AudioMixPlan.normalizationTargetPeak / 0.5

        #expect(isApproximately(Double(audioVolumeRamp.start), expectedGain))
        #expect(isApproximately(Double(audioVolumeRamp.end), expectedGain))
        #expect(await analyzer.requests() == [
            AudioPeakAnalysisRequest(
                inputFileURL: sourceURL,
                timeRange: try TimeRange(start: 1, end: 4),
                audioTracks: [.system]
            )
        ])
    }

    @Test("GIF options participate in undo and export requests")
    func gifOptionsParticipateInUndoAndExportRequests() async throws {
        let exporter = SpyMediaExporter()
        let model = makeModel(exporter: exporter)

        await model.open(fileURL: URL(fileURLWithPath: "/tmp/source.mp4"), outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.setFormat(.gif)
        model.setGIFLoopModeKind(.bounce)
        model.setGIFDithering(.diffusion)

        #expect(model.gifLoopModeKind == .bounce)
        #expect(model.gifDithering == .diffusion)

        model.undoEditorChange()

        #expect(model.gifLoopModeKind == .bounce)
        #expect(model.gifDithering == .auto)

        model.redoEditorChange()

        #expect(model.gifLoopModeKind == .bounce)
        #expect(model.gifDithering == .diffusion)

        model.startExport()
        while model.isExporting {
            try await Task.sleep(for: .milliseconds(10))
        }

        let expectedOptions = try GIFRenderOptions(
            quality: .balanced,
            loopMode: .bounce,
            dithering: .diffusion
        )
        let captured = await exporter.capturedExports()
        #expect(captured.first?.request.format == .gif)
        #expect(captured.first?.request.gifOptions == expectedOptions)
    }

    @Test("trim start changes coalesce into one undo step")
    func trimStartChangesCoalesceIntoOneUndoStep() async throws {
        let model = makeModel()

        await model.open(fileURL: URL(fileURLWithPath: "/tmp/source.mp4"), outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.setTrimStart(1)
        model.setTrimStart(2)
        model.setTrimStart(3)

        #expect(model.trimStart == 3)

        model.undoEditorChange()

        #expect(model.trimStart == 0)
        #expect(!model.canUndoEditorChange)
        #expect(model.canRedoEditorChange)

        model.redoEditorChange()

        #expect(model.trimStart == 3)
    }

    @Test("successful export emits format memory")
    func successfulExportEmitsFormatMemory() async throws {
        var captured: [(ExportFormat, ExportMemory)] = []
        let model = makeModel { format, memory in
            captured.append((format, memory))
        }

        await model.open(fileURL: URL(fileURLWithPath: "/tmp/source.mp4"), outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.setFormat(.hevc)
        model.setSizePreset(.percent50)
        model.setFrameRate(24)
        model.setQuality(.high)
        model.startExport()

        while model.isExporting {
            try await Task.sleep(for: .milliseconds(10))
        }

        let expectedMemory = try ExportMemory(
            sizePreset: .percent50,
            frameRate: FrameRate(24),
            quality: .high
        )
        #expect(captured.count == 1)
        #expect(captured.first?.0 == .hevc)
        #expect(captured.first?.1 == expectedMemory)
    }

    @Test("successful GIF export emits GIF memory")
    func successfulGIFExportEmitsGIFMemory() async throws {
        var captured: [(ExportFormat, ExportMemory)] = []
        let model = makeModel { format, memory in
            captured.append((format, memory))
        }

        await model.open(fileURL: URL(fileURLWithPath: "/tmp/source.mp4"), outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.setFormat(.gif)
        model.setSizePreset(.percent50)
        model.setFrameRate(12)
        model.setQuality(.compact)
        model.setGIFLoopModeKind(.count)
        model.setGIFLoopCount(6)
        model.setGIFDithering(.ordered)
        model.startExport()

        while model.isExporting {
            try await Task.sleep(for: .milliseconds(10))
        }

        let expectedMemory = try ExportMemory(
            sizePreset: .percent50,
            frameRate: FrameRate(12),
            quality: .compact,
            gifOptions: GIFRenderOptions(
                quality: .compact,
                loopMode: .counted(6),
                dithering: .ordered
            )
        )
        #expect(captured.count == 1)
        #expect(captured.first?.0 == .gif)
        #expect(captured.first?.1 == expectedMemory)
    }

    @Test("successful APNG export emits loop memory")
    func successfulAPNGExportEmitsLoopMemory() async throws {
        var captured: [(ExportFormat, ExportMemory)] = []
        let model = makeModel { format, memory in
            captured.append((format, memory))
        }

        await model.open(fileURL: URL(fileURLWithPath: "/tmp/source.mp4"), outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.setFormat(.apng)
        model.setSizePreset(.percent50)
        model.setFrameRate(12)
        model.setGIFLoopModeKind(.none)
        model.startExport()

        while model.isExporting {
            try await Task.sleep(for: .milliseconds(10))
        }

        let expectedMemory = try ExportMemory(
            sizePreset: .percent50,
            frameRate: FrameRate(12),
            quality: .lossless,
            gifOptions: GIFRenderOptions(loopMode: .none)
        )
        #expect(captured.count == 1)
        #expect(captured.first?.0 == .apng)
        #expect(captured.first?.1 == expectedMemory)
    }

    @Test("batch export runs selected formats and exposes job rows")
    func batchExportRunsSelectedFormatsAndExposesJobRows() async throws {
        let exporter = SpyMediaExporter()
        let fileSystem = SpyFileSystem()
        let fileActionClient = StubExportedFileActionClient()
        var rememberedFormats: [ExportFormat] = []
        let model = makeModel(
            exporter: exporter,
            fileSystem: fileSystem,
            fileActionClient: fileActionClient
        ) { format, _ in
            rememberedFormats.append(format)
        }
        let batchDirectory = URL(fileURLWithPath: "/tmp/source Export", isDirectory: true)

        await model.open(fileURL: URL(fileURLWithPath: "/tmp/source.mp4"), outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.setFormatSelection(.hevc, isSelected: true)
        model.setFormatSelection(.gif, isSelected: true)
        model.setGIFLoopModeKind(.bounce)
        model.setGIFDithering(.diffusion)
        model.startExport()

        while model.isExporting {
            try await Task.sleep(for: .milliseconds(10))
        }

        let captured = await exporter.capturedExports()
        let expectedGIFOptions = try GIFRenderOptions(
            quality: .balanced,
            loopMode: .bounce,
            dithering: .diffusion
        )

        #expect(captured.map(\.request.format) == [.mp4, .hevc, .gif])
        #expect(captured[0].request.gifOptions == nil)
        #expect(captured[1].request.gifOptions == nil)
        #expect(captured[2].request.gifOptions == expectedGIFOptions)
        #expect(captured.map(\.outputFileURL.path) == [
            "/tmp/source Export/source Export H264.mp4",
            "/tmp/source Export/source Export H265.mp4",
            "/tmp/source Export/source Export GIF.gif"
        ])
        #expect(fileSystem.createdDirectories == [batchDirectory])
        #expect(model.status == .exportedBatch([
            URL(fileURLWithPath: "/tmp/source Export/source Export H264.mp4"),
            URL(fileURLWithPath: "/tmp/source Export/source Export H265.mp4"),
            URL(fileURLWithPath: "/tmp/source Export/source Export GIF.gif")
        ]))
        #expect(model.exportPanelMessage == "3 files exported")
        #expect(model.exportProgressValue == 1)
        #expect(!model.canRetryExport)
        #expect(model.exportedOpenURL == batchDirectory)
        #expect(model.exportJobs.map(\.format) == [.mp4, .hevc, .gif])
        #expect(model.exportJobs.map(\.statusSummary) == ["Complete", "Complete", "Complete"])
        #expect(model.exportJobs.compactMap(\.fileURL).map(\.path) == [
            "/tmp/source Export/source Export H264.mp4",
            "/tmp/source Export/source Export H265.mp4",
            "/tmp/source Export/source Export GIF.gif"
        ])
        model.openExportedFile()
        #expect(fileActionClient.openedURLs == [batchDirectory])
        #expect(rememberedFormats == [.mp4, .hevc, .gif])
    }

    @Test("unsupported estimate clears stale value")
    func unsupportedEstimateClearsStaleValue() async throws {
        let model = makeModel(exportSizeEstimator: StubFailingExportSizeEstimator())

        model.exportEstimate = try ExportEstimate(bytes: 42, confidence: .modeled)
        await model.open(fileURL: URL(fileURLWithPath: "/tmp/source.mp4"), outputDirectory: URL(fileURLWithPath: "/tmp"))
        await model.refreshExportEstimate()

        #expect(model.exportEstimate == nil)
        #expect(model.exportEstimateSummary == nil)
    }

}
