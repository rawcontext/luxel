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
        let expectedPixelSize = try PixelSize(width: 321, height: 181)

        #expect(exported.format == .gif)
        #expect(exported.pixelSize == expectedPixelSize)
        #expect(exported.shouldMute)
        #expect(metadata.frameCount == 3)
        #expect(metadata.width == 321)
        #expect(metadata.height == 181)

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

    @Test("video formats are rejected")
    func videoFormatsAreRejected() async throws {
        let outputURL = temporaryOutputURL(fileExtension: "mp4")
        let request = try makeRequest(format: .mp4, pixelSize: PixelSize(width: 320, height: 180))

        await #expect(throws: ImageIOAnimatedMediaExporterError.unsupportedFormat(.mp4)) {
            _ = try await ImageIOAnimatedMediaExporter().export(request, to: outputURL)
        }
        #expect(!FileManager.default.fileExists(atPath: outputURL.path))
    }

    private func makeRequest(format: ExportFormat, pixelSize: PixelSize) throws -> ExportRequest {
        try ExportRequest(
            inputFileURL: fixtureURL("input.mp4"),
            format: format,
            pixelSize: pixelSize,
            frameRate: FrameRate(10),
            timeRange: TimeRange(start: 1, end: 1.3),
            shouldMute: false,
            shouldCrop: true
        )
    }

    private func animatedImageMetadata(at fileURL: URL) throws -> (frameCount: Int, width: Int, height: Int) {
        let source = try #require(CGImageSourceCreateWithURL(fileURL as CFURL, nil))
        let properties = try #require(
            CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        )
        let width = try #require(properties[kCGImagePropertyPixelWidth] as? Int)
        let height = try #require(properties[kCGImagePropertyPixelHeight] as? Int)

        return (CGImageSourceGetCount(source), width, height)
    }

    private func fixtureURL(_ fileName: String) throws -> URL {
        try packageRootURL()
            .appending(path: "docs/Luxel/test/fixtures")
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
