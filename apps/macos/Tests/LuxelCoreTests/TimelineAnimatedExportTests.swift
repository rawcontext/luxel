import Foundation
import ImageIO
import LuxelCore
import Testing

@Suite("Timeline animated export")
struct TimelineAnimatedExportTests {
    @Test("gif export samples only kept timeline segments")
    func gifExportAppliesTimelineCuts() async throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appending(path: "luxel-timeline-\(UUID().uuidString).gif")
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
        let source = try #require(CGImageSourceCreateWithURL(outputURL as CFURL, nil))
        #expect(CGImageSourceGetCount(source) == 2)
    }

    private func fixtureURL(_ fileName: String) throws -> URL {
        try sharedFixtureURL(fileName)
    }
}
