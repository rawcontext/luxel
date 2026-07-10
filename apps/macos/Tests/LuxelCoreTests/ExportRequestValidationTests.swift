import Foundation
import LuxelCore
import Testing

extension ExportModelTests {
    @Test("v1 apple-native formats exclude deferred native codec formats")
    func v1AppleNativeFormatsExcludeDeferredNativeCodecFormats() {
        #expect(
            ExportFormat.appleNativeV1Formats == [.hevc, .mp4, .proRes422, .proRes4444, .gif, .apng])
        #expect(ExportFormat.externalNativeCodecFormats == [.webm, .av1])
        #expect(ExportFormat.audioOnlyFormats == [.m4a, .alac, .wav, .caf, .flac])

        for format in ExportFormat.appleNativeV1Formats {
            #expect(format.isAppleNativeV1Format)
            #expect(!format.requiresExternalNativeCodec)
        }

        for format in [ExportFormat.webm, .av1] {
            #expect(!format.isAppleNativeV1Format)
            #expect(format.requiresExternalNativeCodec)
        }

        for format in ExportFormat.audioOnlyFormats {
            #expect(format.isAudioOnlyFormat)
            #expect(!format.requiresExternalNativeCodec)
        }
    }

    @Test("video exports round odd dimensions to even values")
    func videoExportsRoundDimensionsToEvenValues() throws {
        for format in [ExportFormat.mp4, .hevc, .proRes422, .proRes4444, .av1, .webm] {
            let request = try makeRequest(format: format, width: 469, height: 839)

            #expect(try request.outputPixelSize == PixelSize(width: 470, height: 840))
        }
    }

    @Test("non-video exports preserve requested odd dimensions")
    func animatedExportsPreserveOddDimensions() throws {
        for format in [ExportFormat.gif, .apng] + ExportFormat.audioOnlyFormats {
            let request = try makeRequest(format: format, width: 469, height: 839)

            #expect(try request.outputPixelSize == PixelSize(width: 469, height: 839))
        }
    }

    @Test("animated exports always mute output")
    func animatedExportsAlwaysMuteOutput() throws {
        let gifRequest = try makeRequest(format: .gif, shouldMute: false)
        let apngRequest = try makeRequest(format: .apng, shouldMute: false)
        let mp4Request = try makeRequest(format: .mp4, shouldMute: false)

        #expect(gifRequest.outputShouldMute)
        #expect(apngRequest.outputShouldMute)
        #expect(!mp4Request.outputShouldMute)
    }

    @Test("all muted audio mix mutes output")
    func allMutedAudioMixMutesOutput() throws {
        let audioMix = AudioMixPlan(tracks: [
            AudioTrackMix(kind: .system, volume: 0),
            AudioTrackMix(kind: .microphone, isMuted: true)
        ])
        let request = try makeRequest(format: .mp4, shouldMute: false, audioMix: audioMix)

        #expect(!request.shouldMute)
        #expect(request.outputShouldMute)
    }

    @Test("time range exposes trim duration")
    func timeRangeDuration() throws {
        let range = try TimeRange(start: 11.5, end: 27)

        #expect(range.duration == 15.5)
    }

    @Test("progress snapshots expose action text and clamp progress")
    func progressSnapshotsExposeActionTextAndClampProgress() {
        let preparing = ExportProgressSnapshot.preparing(format: .mp4)
        let exporting = ExportProgressSnapshot.exporting(format: .gif, progress: 1.5)
        let enhancing = ExportProgressSnapshot.enhancingAudio(format: .mp4, progress: -1)
        let canceled = ExportProgressSnapshot.canceled(format: .hevc)

        #expect(preparing.phase == .preparing)
        #expect(preparing.actionTitle == "Preparing MP4 (H.264)")
        #expect(preparing.progress == 0)
        #expect(exporting.phase == .exporting)
        #expect(exporting.actionTitle == "Exporting GIF")
        #expect(exporting.progress == 1)
        #expect(enhancing.phase == .enhancingAudio)
        #expect(enhancing.actionTitle == "Enhancing audio…")
        #expect(enhancing.progress == 0)
        #expect(canceled.phase == .canceled)
        #expect(canceled.actionTitle == "Canceled MP4 (HEVC)")
    }

    @Test("export batch requires one source and one time range")
    func exportBatchRequiresOneSourceAndTimeRange() throws {
        let mp4Request = try makeRequest(format: .mp4)
        let hevcRequest = try makeRequest(format: .hevc)

        let batch = try ExportBatch([mp4Request, hevcRequest])

        #expect(batch.requests == [mp4Request, hevcRequest])
    }

    @Test("invalid export batches throw")
    func invalidExportBatchesThrow() throws {
        #expect(throws: ExportModelError.emptyExportBatch) {
            _ = try ExportBatch([])
        }

        let request = try makeRequest(format: .mp4)
        let mixedSourceRequest = try ExportRequest(
            inputFileURL: URL(fileURLWithPath: "/tmp/other.mp4"),
            format: .hevc,
            pixelSize: PixelSize(width: 100, height: 200),
            frameRate: FrameRate(30),
            timeRange: TimeRange(start: 0, end: 10),
            shouldMute: false,
            shouldCrop: true
        )
        let mixedRangeRequest = try ExportRequest(
            inputFileURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            format: .hevc,
            pixelSize: PixelSize(width: 100, height: 200),
            frameRate: FrameRate(30),
            timeRange: TimeRange(start: 1, end: 10),
            shouldMute: false,
            shouldCrop: true
        )

        #expect(throws: ExportModelError.mixedExportBatchSources) {
            _ = try ExportBatch([request, mixedSourceRequest])
        }
        #expect(throws: ExportModelError.mixedExportBatchTimeRanges) {
            _ = try ExportBatch([request, mixedRangeRequest])
        }
    }

    @Test("invalid value objects throw")
    func invalidValuesThrow() {
        #expect(throws: ExportModelError.invalidPixelSize) {
            _ = try PixelSize(width: 0, height: 100)
        }
        #expect(throws: ExportModelError.invalidFrameRate) {
            _ = try FrameRate(0)
        }
        #expect(throws: ExportModelError.invalidPlaybackSpeed) {
            _ = try PlaybackSpeed(0)
        }
        #expect(throws: ExportModelError.invalidTimeRange) {
            _ = try TimeRange(start: 5, end: 5)
        }
        #expect(throws: ExportModelError.invalidEstimateByteCount) {
            _ = try ExportEstimate(bytes: -1, confidence: .modeled)
        }
    }

    func makeRequest(
        format: ExportFormat,
        width: Int = 100,
        height: Int = 200,
        shouldMute: Bool = false,
        audioMix: AudioMixPlan? = nil,
        studioVoiceEnabled: Bool = false,
        quality: ExportQuality = .balanced,
        speed: PlaybackSpeed = .normal,
        gifOptions: GIFRenderOptions? = nil,
        cursorOptions: CursorRenderOptions? = nil,
        keystrokeOptions: KeystrokeRenderOptions? = nil,
        captionOptions: CaptionRenderOptions? = nil,
        cameraOverlay: CameraOverlayPlan? = nil,
        cropRect: CaptureRect? = nil,
        zoomBlocks: [ZoomBlock] = []
    ) throws -> ExportRequest {
        try ExportRequest(
            inputFileURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            format: format,
            pixelSize: PixelSize(width: width, height: height),
            frameRate: FrameRate(30),
            timeRange: TimeRange(start: 0, end: 10),
            shouldMute: shouldMute,
            audioMix: audioMix,
            studioVoiceEnabled: studioVoiceEnabled,
            shouldCrop: true,
            cropRect: cropRect,
            quality: quality,
            speed: speed,
            gifOptions: gifOptions,
            cursorOptions: cursorOptions,
            keystrokeOptions: keystrokeOptions,
            captionOptions: captionOptions,
            cameraOverlay: cameraOverlay,
            zoomBlocks: zoomBlocks
        )
    }

    func zoomBlock(
        start: TimeInterval,
        end: TimeInterval,
        zoom: Double = 1.6
    ) throws -> ZoomBlock {
        try ZoomBlock(
            timeRange: TimeRange(start: start, end: end),
            targetRect: NormalizedRect(x: 0.2, y: 0.3, width: 0.25, height: 0.25),
            zoom: zoom,
            transitionOverride: 0.5
        )
    }
}
