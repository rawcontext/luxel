import Foundation
import ImageIO
import LuxelCore
import Testing

@Suite("Native media exporter")
struct NativeMediaExporterTests {
    @Test("router exports mp4 through native video path")
    func routerExportsMP4ThroughNativeVideoPath() async throws {
        let outputURL = temporaryOutputURL(fileExtension: "mp4")
        let request = try makeRequest(format: .mp4, pixelSize: PixelSize(width: 160, height: 90))

        let exported = try await NativeMediaExporter().export(request, to: outputURL)

        #expect(exported.format == .mp4)
        #expect(FileManager.default.fileExists(atPath: outputURL.path))

        try? FileManager.default.removeItem(at: outputURL)
    }

    @Test("router exports gif through animated image path")
    func routerExportsGIFThroughAnimatedImagePath() async throws {
        let outputURL = temporaryOutputURL(fileExtension: "gif")
        let request = try makeRequest(format: .gif, pixelSize: PixelSize(width: 161, height: 91))

        let exported = try await NativeMediaExporter().export(request, to: outputURL)
        let imageSource = try #require(CGImageSourceCreateWithURL(outputURL as CFURL, nil))

        #expect(exported.format == .gif)
        #expect(CGImageSourceGetCount(imageSource) == 2)

        try? FileManager.default.removeItem(at: outputURL)
    }

    @Test("router rejects formats without native encoders")
    func routerRejectsFormatsWithoutNativeEncoders() async throws {
        for format in [ExportFormat.webm, .av1] {
            let outputURL = temporaryOutputURL(fileExtension: format.fileExtension)
            let request = try makeRequest(format: format, pixelSize: PixelSize(width: 160, height: 90))

            await #expect(throws: NativeMediaExporterError.unsupportedNativeFormat(format)) {
                _ = try await NativeMediaExporter().export(request, to: outputURL)
            }
            #expect(!FileManager.default.fileExists(atPath: outputURL.path))
        }
    }

    private func makeRequest(format: ExportFormat, pixelSize: PixelSize) throws -> ExportRequest {
        try ExportRequest(
            inputFileURL: fixtureURL("input.mp4"),
            format: format,
            pixelSize: pixelSize,
            frameRate: FrameRate(10),
            timeRange: TimeRange(start: 1, end: 1.2),
            shouldMute: true,
            shouldCrop: true
        )
    }

    private func fixtureURL(_ fileName: String) throws -> URL {
        try packageRootURL()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "docs/Luxel/test/fixtures")
            .appending(path: fileName)
    }

    private func temporaryOutputURL(fileExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "luxel-native-export-\(UUID().uuidString)")
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
