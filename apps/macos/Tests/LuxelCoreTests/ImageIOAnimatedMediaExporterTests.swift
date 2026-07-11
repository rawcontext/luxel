import Foundation
import ImageIO
import LuxelCore
import Testing

@Suite("ImageIO animated media exporter")
struct ImageIOAnimatedMediaExporterTests {
    @Test("gif export writes animated image with requested odd dimensions")
    func gifExportWritesAnimatedImageWithRequestedOddDimensions() async throws {
        let outputURL = temporaryOutputURL(fileExtension: "gif")
        let request = try makeRequest(format: .gif, pixelSize: PixelSize(width: 321, height: 181))

        let exported = try await ImageIOAnimatedMediaExporter().export(request, to: outputURL)
        let metadata = try animatedImageMetadata(at: outputURL)
        let data = try Data(contentsOf: outputURL)
        let expectedPixelSize = try PixelSize(width: 321, height: 181)

        #expect(exported.format == .gif)
        #expect(exported.pixelSize == expectedPixelSize)
        #expect(exported.shouldMute)
        #expect(metadata.frameCount == 3)
        #expect(metadata.width == 321)
        #expect(metadata.height == 181)
        #expect(Array(data.prefix(6)) == Array("GIF89a".utf8))
        #expect((data[10] & 0b1000_0000) != 0)
        #expect(data.containsASCII("NETSCAPE2.0"))

        try? FileManager.default.removeItem(at: outputURL)
    }

    @Test("apng export writes animated PNG frames")
    func apngExportWritesAnimatedPNGFrames() async throws {
        let outputURL = temporaryOutputURL(fileExtension: "apng")
        let request = try makeRequest(format: .apng, pixelSize: PixelSize(width: 320, height: 180))

        let exported = try await ImageIOAnimatedMediaExporter().export(request, to: outputURL)
        let metadata = try animatedImageMetadata(at: outputURL)
        let expectedPixelSize = try PixelSize(width: 320, height: 180)

        #expect(exported.format == .apng)
        #expect(exported.pixelSize == expectedPixelSize)
        #expect(exported.shouldMute)
        #expect(metadata.frameCount == 3)
        #expect(metadata.width == 320)
        #expect(metadata.height == 180)

        try? FileManager.default.removeItem(at: outputURL)
    }

    @Test("apng export accepts zoom blocks")
    func apngExportAcceptsZoomBlocks() async throws {
        let outputURL = temporaryOutputURL(fileExtension: "apng")
        let request = try makeRequest(
            format: .apng,
            pixelSize: PixelSize(width: 320, height: 180),
            zoomBlocks: [
                zoomBlock(start: 1, end: 1.3)
            ]
        )

        let exported = try await ImageIOAnimatedMediaExporter().export(request, to: outputURL)
        let metadata = try animatedImageMetadata(at: outputURL)

        #expect(exported.format == .apng)
        #expect(metadata.frameCount == 3)
        #expect(metadata.width == 320)
        #expect(metadata.height == 180)

        try? FileManager.default.removeItem(at: outputURL)
    }

    @Test("apng export honors loop count")
    func apngExportHonorsLoopCount() async throws {
        let outputURL = temporaryOutputURL(fileExtension: "apng")
        let request = try makeRequest(
            format: .apng,
            pixelSize: PixelSize(width: 320, height: 180),
            gifOptions: GIFRenderOptions(loopMode: .count(3))
        )

        _ = try await ImageIOAnimatedMediaExporter().export(request, to: outputURL)
        let metadata = try animatedImageMetadata(at: outputURL)
        let data = try Data(contentsOf: outputURL)

        #expect(metadata.frameCount == 3)
        #expect(try apngLoopCount(in: data) == 3)

        try? FileManager.default.removeItem(at: outputURL)
    }

    @Test("apng export honors bounce loop mode")
    func apngExportHonorsBounceLoopMode() async throws {
        let outputURL = temporaryOutputURL(fileExtension: "apng")
        let request = try makeRequest(
            format: .apng,
            pixelSize: PixelSize(width: 320, height: 180),
            gifOptions: GIFRenderOptions(loopMode: .bounce)
        )

        _ = try await ImageIOAnimatedMediaExporter().export(request, to: outputURL)
        let metadata = try animatedImageMetadata(at: outputURL)
        let data = try Data(contentsOf: outputURL)

        #expect(metadata.frameCount == 5)
        #expect(try apngLoopCount(in: data) == 0)

        try? FileManager.default.removeItem(at: outputURL)
    }

    @Test("gif export applies playback speed to frame delay")
    func gifExportAppliesPlaybackSpeedToFrameDelay() async throws {
        let outputURL = temporaryOutputURL(fileExtension: "gif")
        let request = try makeRequest(
            format: .gif,
            pixelSize: PixelSize(width: 320, height: 180),
            speed: PlaybackSpeed(2)
        )

        _ = try await ImageIOAnimatedMediaExporter().export(request, to: outputURL)
        let metadata = try animatedImageMetadata(at: outputURL)

        #expect(metadata.frameCount == 3)
        #expect(abs(metadata.frameDelay - 0.05) < 0.02)

        try? FileManager.default.removeItem(at: outputURL)
    }

    @Test("gif export samples only kept timeline segments")
    func gifExportAppliesTimelineCuts() async throws {
        let outputURL = temporaryOutputURL(fileExtension: "gif")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let request = try ExportRequest(
            inputFileURL: fixtureURL("input.mp4"),
            format: .gif,
            pixelSize: PixelSize(width: 320, height: 180),
            frameRate: FrameRate(10),
            timeRange: TimeRange(start: 1, end: 1.3),
            shouldMute: true,
            shouldCrop: true,
            editPlan: TimelineEditPlan(cuts: [
                TimelineCut(
                    id: "middle",
                    sourceRange: TimeRange(start: 1.1, end: 1.2),
                    kind: .transcriptSentence
                )
            ])
        )

        _ = try await ImageIOAnimatedMediaExporter().export(request, to: outputURL)
        #expect(try animatedImageMetadata(at: outputURL).frameCount == 2)
    }

    @Test("gif export accepts zoom blocks")
    func gifExportAcceptsZoomBlocks() async throws {
        let outputURL = temporaryOutputURL(fileExtension: "gif")
        let request = try makeRequest(
            format: .gif,
            pixelSize: PixelSize(width: 320, height: 180),
            zoomBlocks: [
                zoomBlock(start: 1, end: 1.3)
            ]
        )

        _ = try await ImageIOAnimatedMediaExporter().export(request, to: outputURL)
        let metadata = try animatedImageMetadata(at: outputURL)

        #expect(metadata.frameCount == 3)
        #expect(metadata.width == 320)
        #expect(metadata.height == 180)

        try? FileManager.default.removeItem(at: outputURL)
    }

    @Test("gif export honors custom render options")
    func gifExportHonorsCustomRenderOptions() async throws {
        let outputURL = temporaryOutputURL(fileExtension: "gif")
        let request = try makeRequest(
            format: .gif,
            pixelSize: PixelSize(width: 320, height: 180),
            gifOptions: GIFRenderOptions(
                quality: .compact,
                loopMode: .bounce,
                dithering: .none
            )
        )

        _ = try await ImageIOAnimatedMediaExporter().export(request, to: outputURL)
        let metadata = try animatedImageMetadata(at: outputURL)

        #expect(metadata.frameCount == 5)

        try? FileManager.default.removeItem(at: outputURL)
    }

    @Test("video formats are rejected")
    func videoFormatsAreRejected() async throws {
        let outputURL = temporaryOutputURL(fileExtension: "mp4")
        let request = try makeRequest(format: .mp4, pixelSize: PixelSize(width: 320, height: 180))

        await #expect(throws: ImageIOAnimatedMediaExporterError.unsupportedFormat(.mp4)) {
            _ = try await ImageIOAnimatedMediaExporter().export(request, to: outputURL)
        }
        #expect(!FileManager.default.fileExists(atPath: outputURL.path))
    }

    private func makeRequest(
        format: ExportFormat,
        pixelSize: PixelSize,
        speed: PlaybackSpeed = .normal,
        gifOptions: GIFRenderOptions? = nil,
        zoomBlocks: [ZoomBlock] = []
    ) throws -> ExportRequest {
        try ExportRequest(
            inputFileURL: fixtureURL("input.mp4"),
            format: format,
            pixelSize: pixelSize,
            frameRate: FrameRate(10),
            timeRange: TimeRange(start: 1, end: 1.3),
            shouldMute: false,
            shouldCrop: true,
            speed: speed,
            gifOptions: gifOptions,
            zoomBlocks: zoomBlocks
        )
    }

    private func zoomBlock(start: TimeInterval, end: TimeInterval) throws -> ZoomBlock {
        try ZoomBlock(
            timeRange: TimeRange(start: start, end: end),
            targetRect: NormalizedRect(x: 0.25, y: 0.25, width: 0.2, height: 0.2),
            zoom: 2,
            transitionOverride: 0.05
        )
    }

    private func animatedImageMetadata(at fileURL: URL) throws -> AnimatedImageMetadata {
        let source = try #require(CGImageSourceCreateWithURL(fileURL as CFURL, nil))
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        let width = try #require(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try #require(properties[kCGImagePropertyPixelHeight] as? Int)
        let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        let pngProperties = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any]
        let frameDelay =
            gifProperties?[kCGImagePropertyGIFUnclampedDelayTime] as? TimeInterval
            ?? gifProperties?[kCGImagePropertyGIFDelayTime] as? TimeInterval
            ?? pngProperties?[kCGImagePropertyAPNGUnclampedDelayTime] as? TimeInterval
            ?? pngProperties?[kCGImagePropertyAPNGDelayTime] as? TimeInterval
            ?? 0

        return AnimatedImageMetadata(
            frameCount: CGImageSourceGetCount(source),
            width: width,
            height: height,
            frameDelay: frameDelay
        )
    }

    private func apngLoopCount(in data: Data) throws -> UInt32 {
        let bytes = Array(data)
        var offset = 8

        while offset + 8 <= bytes.count {
            let length = Int(readBigEndianUInt32(bytes, offset: offset))
            let typeStart = offset + 4
            let dataStart = offset + 8
            let dataEnd = dataStart + length
            let chunkEnd = dataEnd + 4
            guard chunkEnd <= bytes.count else {
                break
            }

            let type = String(bytes: bytes[typeStart..<(typeStart + 4)], encoding: .ascii)
            if type == "acTL" {
                try #require(length == 8)
                return readBigEndianUInt32(bytes, offset: dataStart + 4)
            }

            offset = chunkEnd
        }

        Issue.record("Expected APNG acTL chunk")
        return 0
    }

    private func readBigEndianUInt32(_ bytes: [UInt8], offset: Int) -> UInt32 {
        (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
    }

    private func fixtureURL(_ fileName: String) throws -> URL {
        try packageRootURL()
            .appending(path: "Tests/Fixtures")
            .appending(path: fileName)
    }

    private func temporaryOutputURL(fileExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "luxel-animated-export-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
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

private struct AnimatedImageMetadata {
    let frameCount: Int
    let width: Int
    let height: Int
    let frameDelay: TimeInterval
}

extension Data {
    fileprivate func containsASCII(_ string: String) -> Bool {
        containsSequence(Array(string.utf8))
    }

    private func containsSequence(_ sequence: [UInt8]) -> Bool {
        guard !sequence.isEmpty, count >= sequence.count else {
            return false
        }

        let bytes = Array(self)
        for index in 0...(bytes.count - sequence.count)
        where Array(bytes[index..<(index + sequence.count)]) == sequence {
            return true
        }
        return false
    }
}
