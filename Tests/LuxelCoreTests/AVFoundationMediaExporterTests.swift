import AVFoundation
import CoreMedia
import Foundation
import LuxelCore
import Testing

@Suite("AVFoundation media exporter")
struct AVFoundationMediaExporterTests {
    @Test("mp4 export trims resizes changes frame rate and keeps audio")
    func mp4ExportTrimsResizesChangesFrameRateAndKeepsAudio() async throws {
        let outputURL = temporaryOutputURL(fileExtension: "mp4")
        let request = try ExportRequest(
            inputFileURL: fixtureURL("input@2x.mp4"),
            format: .mp4,
            pixelSize: PixelSize(width: 321, height: 181),
            frameRate: FrameRate(30),
            timeRange: TimeRange(start: 1, end: 1.75),
            shouldMute: false,
            shouldCrop: true
        )

        let exported = try await AVFoundationMediaExporter().export(request, to: outputURL)
        let source = try await AVFoundationMediaMetadataReader().readSourceMedia(at: outputURL)
        let expectedPixelSize = try PixelSize(width: 322, height: 182)
        let expectedFrameRate = try FrameRate(30)

        #expect(exported.fileURL == outputURL)
        #expect(exported.format == .mp4)
        #expect(exported.pixelSize == expectedPixelSize)
        #expect(!exported.shouldMute)
        #expect(source.duration > 0.70)
        #expect(source.duration < 0.80)
        #expect(source.pixelSize == exported.pixelSize)
        #expect(source.nominalFrameRate == expectedFrameRate)
        #expect(source.hasAudio)
        let codecType = try await videoCodecType(at: outputURL)
        #expect(codecType == kCMVideoCodecType_H264)

        try? FileManager.default.removeItem(at: outputURL)
    }

    @Test("hevc export writes HEVC video")
    func hevcExportWritesHEVCVideo() async throws {
        let outputURL = temporaryOutputURL(fileExtension: "mp4")
        let request = try ExportRequest(
            inputFileURL: fixtureURL("input.mp4"),
            format: .hevc,
            pixelSize: PixelSize(width: 320, height: 180),
            frameRate: FrameRate(30),
            timeRange: TimeRange(start: 1, end: 1.5),
            shouldMute: true,
            shouldCrop: false
        )

        let exported = try await AVFoundationMediaExporter().export(request, to: outputURL)
        let source = try await AVFoundationMediaMetadataReader().readSourceMedia(at: outputURL)
        let expectedPixelSize = try PixelSize(width: 320, height: 180)
        let codecType = try await videoCodecType(at: outputURL)

        #expect(exported.format == .hevc)
        #expect(source.pixelSize == expectedPixelSize)
        #expect(codecType == kCMVideoCodecType_HEVC)

        try? FileManager.default.removeItem(at: outputURL)
    }

    @Test("muted mp4 export omits audio tracks")
    func mutedMP4ExportOmitsAudioTracks() async throws {
        let outputURL = temporaryOutputURL(fileExtension: "mp4")
        let request = try ExportRequest(
            inputFileURL: fixtureURL("input@2x.mp4"),
            format: .mp4,
            pixelSize: PixelSize(width: 320, height: 180),
            frameRate: FrameRate(24),
            timeRange: TimeRange(start: 2, end: 2.5),
            shouldMute: true,
            shouldCrop: false
        )

        let exported = try await AVFoundationMediaExporter().export(request, to: outputURL)
        let source = try await AVFoundationMediaMetadataReader().readSourceMedia(at: outputURL)
        let expectedPixelSize = try PixelSize(width: 320, height: 180)
        let expectedFrameRate = try FrameRate(24)

        #expect(exported.shouldMute)
        #expect(source.pixelSize == expectedPixelSize)
        #expect(source.nominalFrameRate == expectedFrameRate)
        #expect(!source.hasAudio)

        try? FileManager.default.removeItem(at: outputURL)
    }

    @Test("unsupported formats are rejected without writing output")
    func unsupportedFormatsAreRejectedWithoutWritingOutput() async throws {
        let outputURL = temporaryOutputURL(fileExtension: "gif")
        let request = try ExportRequest(
            inputFileURL: fixtureURL("input.mp4"),
            format: .gif,
            pixelSize: PixelSize(width: 320, height: 180),
            frameRate: FrameRate(12),
            timeRange: TimeRange(start: 1, end: 1.2),
            shouldMute: false,
            shouldCrop: false
        )

        await #expect(throws: AVFoundationExportPlanError.unsupportedFormat(.gif)) {
            _ = try await AVFoundationMediaExporter().export(request, to: outputURL)
        }
        #expect(!FileManager.default.fileExists(atPath: outputURL.path))
    }

    private func fixtureURL(_ fileName: String) throws -> URL {
        try packageRootURL()
            .appending(path: "docs/Luxel/test/fixtures")
            .appending(path: fileName)
    }

    private func temporaryOutputURL(fileExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "luxel-export-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
    }

    private func videoCodecType(at fileURL: URL) async throws -> CMVideoCodecType {
        let asset = AVURLAsset(url: fileURL)
        let videoTrack = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let formatDescription = try #require(try await videoTrack.load(.formatDescriptions).first)

        return CMFormatDescriptionGetMediaSubType(formatDescription)
    }

    private func packageRootURL() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "Tests" {
            let next = url.deletingLastPathComponent()
            try #require(next.path != url.path)
            url = next
        }

        return url.deletingLastPathComponent()
    }
}
