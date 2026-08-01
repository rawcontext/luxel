import Foundation
import LuxelCore
import Testing

@Suite("Export model")
struct ExportModelTests {
}

extension ExportModelTests {
    @Test("formats map to expected extensions and display names")
    func formatMetadata() {
        #expect(ExportFormat.mp4.fileExtension == "mp4")
        #expect(ExportFormat.hevc.fileExtension == "mp4")
        #expect(ExportFormat.av1.fileExtension == "mp4")
        #expect(ExportFormat.webm.fileExtension == "webm")
        #expect(ExportFormat.proRes422.fileExtension == "mov")
        #expect(ExportFormat.proRes4444.fileExtension == "mov")
        #expect(ExportFormat.gif.fileExtension == "gif")
        #expect(ExportFormat.apng.fileExtension == "apng")
        #expect(ExportFormat.m4a.fileExtension == "m4a")
        #expect(ExportFormat.alac.fileExtension == "m4a")
        #expect(ExportFormat.wav.fileExtension == "wav")
        #expect(ExportFormat.caf.fileExtension == "caf")
        #expect(ExportFormat.flac.fileExtension == "flac")

        #expect(ExportFormat.mp4.prettyName == "MP4 (H.264)")
        #expect(ExportFormat.hevc.prettyName == "MP4 (HEVC)")
        #expect(ExportFormat.av1.prettyName == "MP4 (AV1)")
        #expect(ExportFormat.webm.prettyName == "WebM (VP9)")
        #expect(ExportFormat.proRes422.prettyName == "MOV (ProRes 422)")
        #expect(ExportFormat.proRes4444.prettyName == "MOV (ProRes 4444)")
        #expect(ExportFormat.gif.prettyName == "GIF")
        #expect(ExportFormat.apng.prettyName == "APNG")
        #expect(ExportFormat.m4a.prettyName == "M4A (AAC)")
        #expect(ExportFormat.alac.prettyName == "M4A (Apple Lossless)")
        #expect(ExportFormat.wav.prettyName == "WAV")
        #expect(ExportFormat.caf.prettyName == "CAF")
        #expect(ExportFormat.flac.prettyName == "FLAC")
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

        for format in [ExportFormat.proRes422, .proRes4444] {
            #expect(ExportQuality.availableQualities(for: format) == [.high])
            #expect(ExportQuality.defaultQuality(for: format) == .high)
            #expect(ExportQuality.high.isAvailable(for: format))
            #expect(!ExportQuality.balanced.isAvailable(for: format))
        }

        #expect(ExportQuality.availableQualities(for: .apng) == [.lossless])
        #expect(ExportQuality.defaultQuality(for: .apng) == .lossless)
        #expect(ExportQuality.lossless.isAvailable(for: .apng))
        #expect(!ExportQuality.balanced.isAvailable(for: .apng))

        #expect(ExportQuality.availableQualities(for: .m4a) == [.balanced])
        #expect(ExportQuality.defaultQuality(for: .m4a) == .balanced)
        #expect(ExportQuality.balanced.isAvailable(for: .m4a))
        #expect(!ExportQuality.high.isAvailable(for: .m4a))

        for format in [ExportFormat.alac, .wav, .caf, .flac] {
            #expect(ExportQuality.availableQualities(for: format) == [.lossless])
            #expect(ExportQuality.defaultQuality(for: format) == .lossless)
            #expect(ExportQuality.lossless.isAvailable(for: format))
            #expect(!ExportQuality.balanced.isAvailable(for: format))
        }
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

        #expect(ExportQuality.high.videoBitsPerPixel(for: .proRes422) == 2.35)
        #expect(ExportQuality.high.videoBitsPerPixel(for: .proRes4444) == 5.30)
        #expect(ExportQuality.balanced.videoBitsPerPixel(for: .proRes422) == nil)
        #expect(ExportQuality.balanced.videoBitsPerPixel(for: .proRes4444) == nil)

        for format in [ExportFormat.gif, .apng, .webm, .av1, .m4a, .alac, .wav, .caf, .flac] {
            #expect(ExportQuality.balanced.videoBitsPerPixel(for: format) == nil)
        }
    }

    @Test("export request defaults legacy quality to balanced")
    func exportRequestDefaultsLegacyQualityToBalanced() throws {
        let data = Data(
            """
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
        #expect(!request.shouldApplyStudioVoice)
        #expect(request.cropRect == nil)
        #expect(request.editPlan == .empty)
        expectDefaultOptionalExportFeatures(request)
    }

    @Test("export request round trips transcript edit plan and derives duration")
    func exportRequestRoundTripsEditPlan() throws {
        let editPlan = try TimelineEditPlan(cuts: [
            TimelineCut(
                id: "sentence",
                sourceRange: TimeRange(start: 2, end: 4),
                kind: .transcriptSentence,
                transcriptSpanIDs: ["span"]
            )
        ])
        let request = try ExportRequest(
            inputFileURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            format: .mp4,
            pixelSize: PixelSize(width: 100, height: 200),
            frameRate: FrameRate(30),
            timeRange: TimeRange(start: 0, end: 10),
            shouldMute: false,
            shouldCrop: true,
            speed: PlaybackSpeed(2),
            editPlan: editPlan
        )

        let decoded = try JSONDecoder().decode(
            ExportRequest.self,
            from: JSONEncoder().encode(request)
        )

        #expect(decoded == request)
        #expect(decoded.outputDuration == 4)
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

    @Test("export request round trips Studio Voice and derives effective use")
    func exportRequestRoundTripsStudioVoice() throws {
        let request = try makeRequest(format: .mp4, studioVoiceEnabled: true)

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(ExportRequest.self, from: data)

        #expect(decoded == request)
        #expect(decoded.studioVoiceEnabled)
        #expect(decoded.shouldApplyStudioVoice)

        for format in [ExportFormat.gif, .apng] {
            #expect(!(try makeRequest(format: format, studioVoiceEnabled: true)).shouldApplyStudioVoice)
        }
        #expect(
            !(try makeRequest(
                format: .mp4,
                shouldMute: true,
                studioVoiceEnabled: true
            )).shouldApplyStudioVoice
        )
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
}
