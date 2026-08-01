import AVFoundation
import Foundation
import LuxelCore
import LuxelTestSupport
import Testing

@Suite("AVFoundation passthrough exporter")
struct AVFoundationPassthroughExporterTests {
    @Test("trimmed passthrough writes a shortened movie")
    func trimmedPassthroughWritesShortenedMovie() async throws {
        let outputURL = temporaryOutputURL(fileExtension: "mp4")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let request = try PassthroughExportRequest(
            inputFileURL: fixtureURL("input@2x.mp4"),
            outputFileURL: outputURL,
            timeRange: TimeRange(start: 1, end: 1.5)
        )

        let result = try await AVFoundationPassthroughExporter().export(request)
        let source = try await AVFoundationMediaMetadataReader().readSourceMedia(at: outputURL)

        #expect(result.fileURL == outputURL)
        #expect(source.duration > 0.35)
        #expect(source.duration < 0.70)
        #expect(source.hasAudio)
    }

    @Test("unsupported output extension is rejected")
    func unsupportedOutputExtensionIsRejected() async throws {
        let request = try PassthroughExportRequest(
            inputFileURL: fixtureURL("input.mp4"),
            outputFileURL: temporaryOutputURL(fileExtension: "webm"),
            timeRange: TimeRange(start: 1, end: 1.5)
        )

        await #expect(throws: AVFoundationPassthroughExporterError.unsupportedPathExtension("webm")) {
            _ = try await AVFoundationPassthroughExporter().export(request)
        }
    }

    private func fixtureURL(_ fileName: String) throws -> URL {
        try testFixtureURL(fileName)
    }

    private func temporaryOutputURL(fileExtension: String) -> URL {
        temporaryTestFileURL(prefix: "luxel-passthrough-", pathExtension: fileExtension)
    }
}
