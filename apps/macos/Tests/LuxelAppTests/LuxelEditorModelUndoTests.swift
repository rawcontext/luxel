import AVFoundation
import Foundation
import LuxelCore
import Testing

@testable import LuxelPresentation

extension LuxelEditorModelTests {
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

        await model.open(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            outputDirectory: URL(fileURLWithPath: "/tmp"))
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

        await model.open(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            outputDirectory: URL(fileURLWithPath: "/tmp"))
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

        await model.open(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            outputDirectory: URL(fileURLWithPath: "/tmp"))
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

        await model.open(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            outputDirectory: URL(fileURLWithPath: "/tmp"))
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

        await model.open(
            fileURL: try fixtureURL("input@2x.mp4"), outputDirectory: URL(fileURLWithPath: "/tmp"))

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
        #expect(
            await analyzer.requests() == [
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

        await model.open(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            outputDirectory: URL(fileURLWithPath: "/tmp"))
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

        await model.open(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            outputDirectory: URL(fileURLWithPath: "/tmp"))
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
}
