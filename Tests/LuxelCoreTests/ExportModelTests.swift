import Foundation
import LuxelCore
import Testing

@Suite("Export model")
struct ExportModelTests {
    @Test("video formats map to expected extensions and display names")
    func formatMetadata() {
        #expect(ExportFormat.mp4.fileExtension == "mp4")
        #expect(ExportFormat.hevc.fileExtension == "mp4")
        #expect(ExportFormat.av1.fileExtension == "mp4")
        #expect(ExportFormat.webm.fileExtension == "webm")
        #expect(ExportFormat.gif.fileExtension == "gif")
        #expect(ExportFormat.apng.fileExtension == "apng")

        #expect(ExportFormat.mp4.prettyName == "MP4 (H264)")
        #expect(ExportFormat.hevc.prettyName == "MP4 (H265)")
        #expect(ExportFormat.av1.prettyName == "MP4 (AV1)")
        #expect(ExportFormat.webm.prettyName == "WebM")
        #expect(ExportFormat.gif.prettyName == "GIF")
        #expect(ExportFormat.apng.prettyName == "APNG")
    }

    @Test("quality exposes format availability and labels")
    func qualityAvailability() {
        #expect(ExportQuality.compact.label == "Compact")
        #expect(ExportQuality.balanced.label == "Balanced")
        #expect(ExportQuality.high.label == "High")
        #expect(ExportQuality.lossless.label == "Lossless")

        for format in [ExportFormat.mp4, .hevc, .gif, .webm, .av1] {
            #expect(ExportQuality.availableQualities(for: format) == [.compact, .balanced, .high])
            #expect(ExportQuality.defaultQuality(for: format) == .balanced)
            #expect(ExportQuality.high.isAvailable(for: format))
            #expect(!ExportQuality.lossless.isAvailable(for: format))
        }

        #expect(ExportQuality.availableQualities(for: .apng) == [.lossless])
        #expect(ExportQuality.defaultQuality(for: .apng) == .lossless)
        #expect(ExportQuality.lossless.isAvailable(for: .apng))
        #expect(!ExportQuality.balanced.isAvailable(for: .apng))
    }

    @Test("quality maps video bitrates for apple native movie formats")
    func qualityMapsVideoBitrates() {
        #expect(ExportQuality.compact.videoBitsPerPixel(for: .mp4) == 0.07)
        #expect(ExportQuality.balanced.videoBitsPerPixel(for: .mp4) == 0.12)
        #expect(ExportQuality.high.videoBitsPerPixel(for: .mp4) == 0.20)
        #expect(ExportQuality.lossless.videoBitsPerPixel(for: .mp4) == nil)

        #expect(ExportQuality.compact.videoBitsPerPixel(for: .hevc) == 0.05)
        #expect(ExportQuality.balanced.videoBitsPerPixel(for: .hevc) == 0.09)
        #expect(ExportQuality.high.videoBitsPerPixel(for: .hevc) == 0.15)
        #expect(ExportQuality.lossless.videoBitsPerPixel(for: .hevc) == nil)

        for format in [ExportFormat.gif, .apng, .webm, .av1] {
            #expect(ExportQuality.balanced.videoBitsPerPixel(for: format) == nil)
        }
    }

    @Test("export request defaults legacy quality to balanced")
    func exportRequestDefaultsLegacyQualityToBalanced() throws {
        let data = Data("""
        {
          "inputFileURL": "file:///tmp/input.mp4",
          "format": "mp4",
          "pixelSize": { "width": 100, "height": 200 },
          "frameRate": { "framesPerSecond": 30 },
          "timeRange": { "start": 0, "end": 10 },
          "shouldMute": false,
          "shouldCrop": true
        }
        """.utf8)

        let request = try JSONDecoder().decode(ExportRequest.self, from: data)

        #expect(request.quality == .balanced)
        #expect(request.resolvedQuality == .balanced)
        #expect(request.speed == .normal)
        #expect(request.gifOptions == nil)
        #expect(request.audioMix == nil)
        #expect(request.cropRect == nil)
        #expect(request.cursorOptions == nil)
        #expect(request.keystrokeOptions == nil)
        #expect(request.captionOptions == nil)
        #expect(request.cameraOverlay == nil)
        #expect(request.zoomBlocks.isEmpty)
    }

    @Test("export request round trips GIF options")
    func exportRequestRoundTripsGIFOptions() throws {
        let gifOptions = try GIFRenderOptions(
            loopMode: .counted(2),
            dithering: .diffusion,
            paletteSize: 128,
            lossyTolerance: 8
        )
        let request = try makeRequest(format: .gif, gifOptions: gifOptions)

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(ExportRequest.self, from: data)

        #expect(decoded == request)
        #expect(decoded.gifOptions == gifOptions)
    }

    @Test("export request round trips audio mix")
    func exportRequestRoundTripsAudioMix() throws {
        let audioMix = AudioMixPlan(
            tracks: [
                AudioTrackMix(kind: .system, volume: 0.4),
                AudioTrackMix(kind: .microphone, volume: 1.3)
            ],
            normalizePeak: true
        )
        let request = try makeRequest(format: .mp4, audioMix: audioMix)

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(ExportRequest.self, from: data)

        #expect(decoded == request)
        #expect(decoded.audioMix == audioMix)
        #expect(!decoded.outputShouldMute)
    }

    @Test("export request round trips source crop rect")
    func exportRequestRoundTripsSourceCropRect() throws {
        let cropRect = try CaptureRect(x: 12, y: 18, width: 80, height: 60)
        let request = try makeRequest(format: .mp4, cropRect: cropRect)

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(ExportRequest.self, from: data)

        #expect(decoded == request)
        #expect(decoded.cropRect == cropRect)
    }

    @Test("export request round trips sidecar render options")
    func exportRequestRoundTripsSidecarRenderOptions() throws {
        let cursorOptions = try CursorRenderOptions(sizeMultiplier: 2, smoothing: .medium)
        let keystrokeOptions = try KeystrokeRenderOptions(anchor: .bottomRight, theme: .lightGlass)
        let captionOptions = CaptionRenderOptions(burnIn: true, theme: .outlinedText)
        let request = try makeRequest(
            format: .mp4,
            cursorOptions: cursorOptions,
            keystrokeOptions: keystrokeOptions,
            captionOptions: captionOptions
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(ExportRequest.self, from: data)

        #expect(decoded == request)
        #expect(decoded.cursorOptions == cursorOptions)
        #expect(decoded.keystrokeOptions == keystrokeOptions)
        #expect(decoded.captionOptions == captionOptions)
    }

    @Test("export request round trips camera overlay")
    func exportRequestRoundTripsCameraOverlay() throws {
        let cameraOverlay = try CameraOverlayPlan(
            placement: .anchor(.topLeft),
            widthFraction: 0.35,
            shape: .roundedRect,
            showsBorder: false
        )
        let request = try makeRequest(format: .mp4, cameraOverlay: cameraOverlay)

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(ExportRequest.self, from: data)

        #expect(decoded == request)
        #expect(decoded.cameraOverlay == cameraOverlay)
    }

    @Test("export request round trips zoom blocks")
    func exportRequestRoundTripsZoomBlocks() throws {
        let zoomBlocks = [
            try zoomBlock(start: 1, end: 3),
            try zoomBlock(start: 5, end: 8, zoom: 2.2)
        ]
        let request = try makeRequest(format: .mp4, zoomBlocks: zoomBlocks)

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(ExportRequest.self, from: data)

        #expect(decoded == request)
        #expect(decoded.zoomBlocks == zoomBlocks)
    }

    @Test("export request falls back from unavailable quality")
    func exportRequestFallsBackFromUnavailableQuality() throws {
        let request = try makeRequest(format: .apng, quality: .balanced)

        #expect(request.quality == .balanced)
        #expect(request.resolvedQuality == .lossless)
    }

    @Test("playback speed validates bounds and compares with tolerance")
    func playbackSpeedValidatesBounds() throws {
        #expect(try PlaybackSpeed(0.1).value == 0.1)
        #expect(try PlaybackSpeed(10).value == 10)
        #expect(try PlaybackSpeed(1.000_000_4) == .normal)

        #expect(throws: ExportModelError.invalidPlaybackSpeed) {
            _ = try PlaybackSpeed(0.09)
        }
        #expect(throws: ExportModelError.invalidPlaybackSpeed) {
            _ = try PlaybackSpeed(10.01)
        }
        #expect(throws: ExportModelError.invalidPlaybackSpeed) {
            _ = try PlaybackSpeed(.infinity)
        }
    }

    @Test("export request derives output duration from playback speed")
    func exportRequestOutputDurationUsesPlaybackSpeed() throws {
        let slow = try makeRequest(format: .mp4, speed: PlaybackSpeed(0.5))
        let fast = try makeRequest(format: .mp4, speed: PlaybackSpeed(2))

        #expect(slow.outputDuration == 20)
        #expect(fast.outputDuration == 5)
    }

    @Test("v1 apple-native formats exclude deferred native codec formats")
    func v1AppleNativeFormatsExcludeDeferredNativeCodecFormats() {
        #expect(ExportFormat.appleNativeV1Formats == [.mp4, .hevc, .gif, .apng])
        #expect(ExportFormat.externalNativeCodecFormats == [.webm, .av1])

        for format in ExportFormat.appleNativeV1Formats {
            #expect(format.isAppleNativeV1Format)
            #expect(!format.requiresExternalNativeCodec)
        }

        for format in [ExportFormat.webm, .av1] {
            #expect(!format.isAppleNativeV1Format)
            #expect(format.requiresExternalNativeCodec)
        }
    }

    @Test("video exports round odd dimensions to even values")
    func videoExportsRoundDimensionsToEvenValues() throws {
        for format in [ExportFormat.mp4, .hevc, .av1, .webm] {
            let request = try makeRequest(format: format, width: 469, height: 839)

            #expect(try request.outputPixelSize == PixelSize(width: 470, height: 840))
        }
    }

    @Test("animated image exports preserve requested odd dimensions")
    func animatedExportsPreserveOddDimensions() throws {
        for format in [ExportFormat.gif, .apng] {
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
        let canceled = ExportProgressSnapshot.canceled(format: .hevc)

        #expect(preparing.phase == .preparing)
        #expect(preparing.actionTitle == "Preparing MP4 (H264)")
        #expect(preparing.progress == 0)
        #expect(exporting.phase == .exporting)
        #expect(exporting.actionTitle == "Exporting GIF")
        #expect(exporting.progress == 1)
        #expect(canceled.phase == .canceled)
        #expect(canceled.actionTitle == "Canceled MP4 (H265)")
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

    private func makeRequest(
        format: ExportFormat,
        width: Int = 100,
        height: Int = 200,
        shouldMute: Bool = false,
        audioMix: AudioMixPlan? = nil,
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

    private func zoomBlock(
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
