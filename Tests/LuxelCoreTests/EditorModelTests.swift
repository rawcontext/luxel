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

        #expect(request.inputFileURL == source.fileURL)
        #expect(request.format == .mp4)
        #expect(request.pixelSize == source.pixelSize)
        #expect(request.frameRate == source.nominalFrameRate)
        #expect(request.timeRange == fullRange)
        #expect(!request.shouldMute)
        #expect(!request.shouldCrop)
        #expect(request.quality == .balanced)
        #expect(request.speed == .normal)
    }

    @Test("draft applies trim resize frame rate and mute overrides")
    func draftAppliesOverrides() throws {
        let draft = try EditorExportDraft(
            source: makeSource(),
            format: .gif,
            trimRange: TimeRange(start: 1, end: 5),
            pixelSize: PixelSize(width: 320, height: 200),
            frameRate: FrameRate(12),
            shouldMute: true,
            shouldCrop: true,
            quality: .high,
            speed: PlaybackSpeed(2)
        )

        let request = try draft.exportRequest
        let pixelSize = try PixelSize(width: 320, height: 200)
        let frameRate = try FrameRate(12)
        let trimRange = try TimeRange(start: 1, end: 5)

        #expect(request.format == .gif)
        #expect(request.pixelSize == pixelSize)
        #expect(request.frameRate == frameRate)
        #expect(request.timeRange == trimRange)
        #expect(request.outputShouldMute)
        #expect(request.shouldCrop)
        #expect(request.quality == .high)
        #expect(request.speed == (try PlaybackSpeed(2)))
        #expect(request.outputDuration == 2)
    }

    @Test("draft decodes missing quality and speed as defaults")
    func draftDecodesMissingQualityAndSpeedAsDefaults() throws {
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
        #expect(try draft.exportRequest.quality == .balanced)
        #expect(try draft.exportRequest.speed == .normal)
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

    private func makeSource(hasAudio: Bool = true) throws -> SourceMedia {
        try SourceMedia(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            duration: 12.5,
            pixelSize: PixelSize(width: 1280, height: 720),
            nominalFrameRate: FrameRate(30),
            hasAudio: hasAudio
        )
    }
}
