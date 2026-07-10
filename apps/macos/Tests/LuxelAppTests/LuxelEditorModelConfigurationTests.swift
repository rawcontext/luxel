import AVFoundation
import Foundation
import LuxelCore
import Testing

@testable import LuxelPresentation

extension LuxelEditorModelTests {
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

        await model.open(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            outputDirectory: URL(fileURLWithPath: "/tmp"))
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
        let captured = await estimator.request(for: .hevc)

        #expect(model.exportEstimate == expectedEstimate)
        #expect(model.exportEstimateSummary(for: .hevc) == "~ 1.5 MB")
        #expect(Set(model.exportEstimatesByFormat.keys) == Set(model.supportedFormats))
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

        await model.open(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.setFormat(.gif)
        model.setQuality(.compact)
        model.setGIFLoopModeKind(.bounce)
        model.setGIFDithering(.diffusion)
        await model.refreshExportEstimate()

        let captured = await estimator.request(for: .gif)
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

        await model.open(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.setFormat(.apng)
        model.setGIFLoopModeKind(.bounce)
        await model.refreshExportEstimate()

        let captured = await estimator.request(for: .apng)
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

        await model.open(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            outputDirectory: URL(fileURLWithPath: "/tmp"))

        model.setFormatSelection(.mp4, isSelected: false)
        #expect(model.selectedFormats == [.mp4])
        #expect(model.selectedFormatSummary == "MP4 (H.264)")

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

        #expect(defaultModel.supportedFormats == [.hevc, .mp4, .proRes422, .proRes4444, .gif, .apng])
        defaultModel.setFormat(.webm)
        #expect(defaultModel.format == .mp4)
        #expect(defaultModel.selectedFormats == [.mp4])
        defaultModel.setFormatSelection(.webm, isSelected: true)
        #expect(defaultModel.selectedFormats == [.mp4])

        let codecModel = makeModel(
            codecAvailability: try CodecAvailability(registeredExternalFormats: [.webm])
        )

        #expect(
            codecModel.supportedFormats == [.webm, .hevc, .mp4, .proRes422, .proRes4444, .gif, .apng])
        #expect(codecModel.format == .webm)
        #expect(codecModel.selectedFormats == [.webm])

        codecModel.setFormatSelection(.mp4, isSelected: true)
        #expect(codecModel.format == .mp4)
        #expect(codecModel.selectedFormats == [.webm, .mp4])
    }

    @Test("remembered export format overrides default WebM selection")
    func rememberedExportFormatOverridesDefaultWebMSelection() async throws {
        let model = makeModel(
            codecAvailability: try CodecAvailability(registeredExternalFormats: [.webm]),
            lastSelectedExportFormat: .hevc
        )

        await model.open(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            outputDirectory: URL(fileURLWithPath: "/tmp"))

        #expect(model.format == .hevc)
        #expect(model.selectedFormats == [.hevc])
    }

    @Test("unsupported remembered export format falls back to WebM")
    func unsupportedRememberedExportFormatFallsBackToWebM() async throws {
        let model = makeModel(
            codecAvailability: try CodecAvailability(registeredExternalFormats: [.webm]),
            lastSelectedExportFormat: .av1
        )

        await model.open(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            outputDirectory: URL(fileURLWithPath: "/tmp"))

        #expect(model.format == .webm)
        #expect(model.selectedFormats == [.webm])
    }

    @Test("format changes remember last selected export format")
    func formatChangesRememberLastSelectedExportFormat() async throws {
        var rememberedFormats: [ExportFormat] = []
        let model = makeModel(
            codecAvailability: try CodecAvailability(registeredExternalFormats: [.webm]),
            onLastSelectedExportFormatChange: { format in
                rememberedFormats.append(format)
            }
        )

        await model.open(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.setFormat(.hevc)
        model.setFormatSelection(.gif, isSelected: true)
        model.setFormatSelection(.gif, isSelected: false)

        #expect(rememberedFormats == [.hevc, .gif, .hevc])
        #expect(model.format == .hevc)
        #expect(model.selectedFormats == [.hevc])
    }

    @Test("renaming source file moves file and updates loaded source")
    func renamingSourceFileMovesFileAndUpdatesLoadedSource() async throws {
        let directory = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let sourceURL = directory.appending(path: "Original.mp4").standardizedFileURL
        try Data([0]).write(to: sourceURL)
        let model = makeModel(fileSystem: LocalFileSystem())
        var renamedFrom: URL?
        var renamedTo: URL?
        model.configureSourceFileRename { oldURL, newURL in
            renamedFrom = oldURL
            renamedTo = newURL
        }

        await model.open(fileURL: sourceURL, outputDirectory: directory)
        model.renameSourceFile(to: "Renamed")

        let renamedURL = directory.appending(path: "Renamed.mp4").standardizedFileURL
        #expect(model.source?.fileURL == renamedURL)
        #expect(model.status == .ready)
        #expect(renamedFrom?.standardizedFileURL == sourceURL)
        #expect(renamedTo?.standardizedFileURL == renamedURL)
        #expect(!FileManager.default.fileExists(atPath: sourceURL.path))
        #expect(FileManager.default.fileExists(atPath: renamedURL.path))
    }

    @Test("export memory seeds controls when opening and changing formats")
    func exportMemorySeedsControlsWhenOpeningAndChangingFormats() async throws {
        let model = makeModel(exportMemory: try exportMemoryFixture())

        await model.open(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            outputDirectory: URL(fileURLWithPath: "/tmp"))

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

    private func exportMemoryFixture() throws -> [ExportFormat: ExportMemory] {
        let gifOptions = try GIFRenderOptions(
            quality: .compact,
            loopMode: .counted(4),
            dithering: .ordered
        )
        return [
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
    }
}
