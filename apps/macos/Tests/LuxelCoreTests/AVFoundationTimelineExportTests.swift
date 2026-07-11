import Foundation
import LuxelCore
import Testing

extension AVFoundationMediaExporterTests {
    @Test("mp4 export stitches kept video and audio segments before speed scaling")
    func mp4ExportAppliesTimelineCutsAndSpeed() async throws {
        let outputURL = temporaryOutputURL(fileExtension: "mp4")
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let request = try ExportRequest(
            inputFileURL: fixtureURL("input@2x.mp4"),
            format: .mp4,
            pixelSize: PixelSize(width: 320, height: 180),
            frameRate: FrameRate(30),
            timeRange: TimeRange(start: 1, end: 1.8),
            shouldMute: false,
            shouldCrop: false,
            speed: PlaybackSpeed(2),
            editPlan: TimelineEditPlan(cuts: [
                TimelineCut(
                    id: "middle",
                    sourceRange: TimeRange(start: 1.2, end: 1.5),
                    kind: .transcriptSentence
                )
            ])
        )

        _ = try await AVFoundationMediaExporter().export(request, to: outputURL)
        let source = try await AVFoundationMediaMetadataReader().readSourceMedia(at: outputURL)

        #expect(source.duration > 0.20)
        #expect(source.duration < 0.30)
        #expect(source.hasAudio)
    }

    @Test("audio-only export stitches kept segments")
    func audioOnlyExportAppliesTimelineCuts() async throws {
        let inputURL = temporaryOutputURL(fileExtension: "m4a")
        let outputURL = temporaryOutputURL(fileExtension: "m4a")
        defer {
            try? FileManager.default.removeItem(at: inputURL)
            try? FileManager.default.removeItem(at: outputURL)
        }
        try writeSilentAudioFixture(to: inputURL, duration: 1)
        let request = try ExportRequest(
            inputFileURL: inputURL,
            format: .m4a,
            pixelSize: PixelSize(width: 1, height: 1),
            frameRate: FrameRate(1),
            timeRange: TimeRange(start: 0, end: 0.5),
            shouldMute: false,
            shouldCrop: false,
            editPlan: TimelineEditPlan(cuts: [
                TimelineCut(
                    id: "middle",
                    sourceRange: TimeRange(start: 0.15, end: 0.35),
                    kind: .transcriptSentence
                )
            ])
        )

        _ = try await AVFoundationMediaExporter().export(request, to: outputURL)
        let source = try await AVFoundationMediaMetadataReader().readSourceMedia(at: outputURL)

        #expect(source.duration > 0.25)
        #expect(source.duration < 0.35)
        #expect(source.isAudioOnly)
    }
}
