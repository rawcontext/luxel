import Foundation
import LuxelCore
import Testing

extension AVFoundationMediaExporterTests {
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
}
