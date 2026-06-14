import Foundation
import LuxelCore
import Testing

@Suite("Editor model")
struct EditorModelTests {
    @Test("draft creates export request from source defaults")
    func draftCreatesExportRequestFromSourceDefaults() throws {
        let source = try makeSource()
        let draft = EditorExportDraft(source: source)

        let request = try draft.exportRequest
        let fullRange = try TimeRange(start: 0, end: 12.5)

        #expect(draft.zoomBlocks.isEmpty)
        #expect(request.inputFileURL == source.fileURL)
        #expect(request.format == .mp4)
        #expect(request.pixelSize == source.pixelSize)
        #expect(request.frameRate == source.nominalFrameRate)
        #expect(request.timeRange == fullRange)
        #expect(!request.shouldMute)
        #expect(request.audioMix == nil)
        #expect(!request.shouldCrop)
        #expect(request.quality == .balanced)
        #expect(request.speed == .normal)
        #expect(request.gifOptions == nil)
        #expect(request.cursorOptions == nil)
        #expect(request.keystrokeOptions == nil)
        #expect(request.captionOptions == nil)
        #expect(request.cameraOverlay == nil)
        #expect(request.zoomBlocks.isEmpty)
    }

    @Test("draft applies trim resize frame rate and mute overrides")
    func draftAppliesOverrides() throws {
        let gifOptions = try GIFRenderOptions(
            loopMode: .bounce,
            dithering: .ordered,
            paletteSize: 128,
            lossyTolerance: 4
        )
        let cursorOptions = try CursorRenderOptions(sizeMultiplier: 1.5, clickStyle: .filledPulse)
        let keystrokeOptions = try KeystrokeRenderOptions(anchor: .topRight, size: .large, displayDuration: 2)
        let captionOptions = CaptionRenderOptions(burnIn: true, position: .top, size: .large)
        let cameraOverlay = try CameraOverlayPlan(
            placement: .normalizedPoint(try NormalizedPoint(x: 0.25, y: 0.3)),
            widthFraction: 0.3,
            shape: .roundedRect,
            showsBorder: false
        )
        let zoomBlocks = [
            try zoomBlock(start: 1.5, end: 3.5)
        ]
        let audioMix = AudioMixPlan(
            tracks: [
                AudioTrackMix(kind: .system, volume: 0.75),
                AudioTrackMix(kind: .microphone, volume: 0.5, isMuted: true)
            ],
            normalizePeak: true
        )
        let draft = try EditorExportDraft(
            source: makeSource(),
            format: .gif,
            trimRange: TimeRange(start: 1, end: 5),
            pixelSize: PixelSize(width: 320, height: 200),
            frameRate: FrameRate(12),
            shouldMute: true,
            audioMix: audioMix,
            shouldCrop: true,
            quality: .high,
            speed: PlaybackSpeed(2),
            gifOptions: gifOptions,
            cursorOptions: cursorOptions,
            keystrokeOptions: keystrokeOptions,
            captionOptions: captionOptions,
            cameraOverlay: cameraOverlay,
            zoomBlocks: zoomBlocks
        )

        let data = try JSONEncoder().encode(draft)
        let decodedDraft = try JSONDecoder().decode(EditorExportDraft.self, from: data)
        let request = try draft.exportRequest
        let pixelSize = try PixelSize(width: 320, height: 200)
        let frameRate = try FrameRate(12)
        let trimRange = try TimeRange(start: 1, end: 5)

        #expect(decodedDraft == draft)
        #expect(request.format == .gif)
        #expect(request.pixelSize == pixelSize)
        #expect(request.frameRate == frameRate)
        #expect(request.timeRange == trimRange)
        #expect(request.outputShouldMute)
        #expect(request.audioMix == audioMix)
        #expect(request.shouldCrop)
        #expect(request.quality == .high)
        #expect(request.speed == (try PlaybackSpeed(2)))
        #expect(request.gifOptions == gifOptions)
        #expect(request.cursorOptions == cursorOptions)
        #expect(request.keystrokeOptions == keystrokeOptions)
        #expect(request.captionOptions == captionOptions)
        #expect(request.cameraOverlay == cameraOverlay)
        #expect(request.zoomBlocks == zoomBlocks)
        #expect(request.outputDuration == 2)
    }

    @Test("draft decodes missing quality speed and GIF options as defaults")
    func draftDecodesMissingQualitySpeedAndGIFOptionsAsDefaults() throws {
        let source = try makeSource()
        let encoder = JSONEncoder()
        let sourceData = try encoder.encode(source)
        let sourceJSON = try #require(String(data: sourceData, encoding: .utf8))
        let data = Data("""
        {
          "source": \(sourceJSON),
          "format": "mp4",
          "shouldMute": false,
          "shouldCrop": false
        }
        """.utf8)

        let draft = try JSONDecoder().decode(EditorExportDraft.self, from: data)

        #expect(draft.quality == .balanced)
        #expect(draft.speed == .normal)
        #expect(draft.gifOptions == nil)
        #expect(draft.audioMix == nil)
        #expect(draft.cursorOptions == nil)
        #expect(draft.keystrokeOptions == nil)
        #expect(draft.captionOptions == nil)
        #expect(draft.cameraOverlay == nil)
        #expect(draft.zoomBlocks.isEmpty)
        #expect(try draft.exportRequest.quality == .balanced)
        #expect(try draft.exportRequest.speed == .normal)
        #expect(try draft.exportRequest.gifOptions == nil)
        #expect(try draft.exportRequest.audioMix == nil)
        #expect(try draft.exportRequest.cursorOptions == nil)
        #expect(try draft.exportRequest.keystrokeOptions == nil)
        #expect(try draft.exportRequest.captionOptions == nil)
        #expect(try draft.exportRequest.cameraOverlay == nil)
        #expect(try draft.exportRequest.zoomBlocks.isEmpty)
    }

    @Test("source media decodes missing alpha as false")
    func sourceMediaDecodesMissingAlphaAsFalse() throws {
        let data = Data("""
        {
          "fileURL": "file:///tmp/source.mp4",
          "duration": 12.5,
          "pixelSize": {
            "width": 1280,
            "height": 720
          },
          "nominalFrameRate": {
            "framesPerSecond": 30
          },
          "hasAudio": true
        }
        """.utf8)

        let source = try JSONDecoder().decode(SourceMedia.self, from: data)

        #expect(!source.hasAlpha)
        #expect(source.hasAudio)
        #expect(source.audioTracks == [.system])
    }

    @Test("source media preserves explicit alpha flag")
    func sourceMediaPreservesExplicitAlphaFlag() throws {
        let source = try makeSource(hasAlpha: true)

        let data = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(SourceMedia.self, from: data)

        #expect(decoded.hasAlpha)
        #expect(decoded == source)
    }

    @Test("source media stores explicit audio tracks and derives audio flag")
    func sourceMediaStoresExplicitAudioTracksAndDerivesAudioFlag() throws {
        let source = try makeSource(audioTracks: [.system, .microphone])

        let data = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(SourceMedia.self, from: data)

        #expect(source.hasAudio)
        #expect(source.audioTracks == [.system, .microphone])
        #expect(decoded == source)
    }

    @Test("source media without audio mutes export request")
    func sourceMediaWithoutAudioMutesExportRequest() throws {
        let draft = try EditorExportDraft(source: makeSource(hasAudio: false))

        #expect(try draft.exportRequest.outputShouldMute)
    }

    @Test("source media requires positive duration")
    func sourceMediaRequiresPositiveDuration() throws {
        #expect(throws: EditorModelError.invalidDuration) {
            _ = try SourceMedia(
                fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
                duration: 0,
                pixelSize: PixelSize(width: 1280, height: 720),
                nominalFrameRate: FrameRate(30),
                hasAudio: true
            )
        }
    }

    @Test("playback loop stays inside selected trim range")
    func playbackLoopStaysInsideSelectedTrimRange() throws {
        let loop = try EditorPlaybackLoop(trimRange: TimeRange(start: 2, end: 5))

        #expect(loop.seekTarget(for: 2) == nil)
        #expect(loop.seekTarget(for: 4.9) == nil)
    }

    @Test("playback loop seeks to trim start outside selected range")
    func playbackLoopSeeksToTrimStartOutsideSelectedRange() throws {
        let loop = try EditorPlaybackLoop(trimRange: TimeRange(start: 2, end: 5))

        #expect(loop.seekTarget(for: 1.9) == 2)
        #expect(loop.seekTarget(for: 5) == 2)
        #expect(loop.seekTarget(for: 5.1) == 2)
    }

    private func makeSource(
        hasAudio: Bool = true,
        hasAlpha: Bool = false,
        audioTracks: [AudioTrackKind]? = nil
    ) throws -> SourceMedia {
        try SourceMedia(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            duration: 12.5,
            pixelSize: PixelSize(width: 1280, height: 720),
            nominalFrameRate: FrameRate(30),
            hasAudio: hasAudio,
            hasAlpha: hasAlpha,
            audioTracks: audioTracks
        )
    }

    private func zoomBlock(start: TimeInterval, end: TimeInterval) throws -> ZoomBlock {
        try ZoomBlock(
            timeRange: TimeRange(start: start, end: end),
            targetRect: NormalizedRect(x: 0.25, y: 0.25, width: 0.25, height: 0.25),
            zoom: 1.6,
            transitionOverride: 0.4
        )
    }
}
