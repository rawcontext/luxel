import AVFoundation
import Foundation
import LuxelCore
import Testing

@Suite("Editor preview asset builder")
struct EditorPreviewAssetBuilderTests {
    @Test("builds stitched video and audio preview tracks")
    func buildsStitchedPreviewTracks() async throws {
        let asset = try await AVFoundationEditorPreviewAssetBuilder().makePreviewAsset(
            inputFileURL: fixtureURL("input@2x.mp4"),
            sourceSegments: [
                SourceMediaSegment(
                    sourceRange: TimeRange(start: 1, end: 1.1),
                    outputStart: 0
                ),
                SourceMediaSegment(
                    sourceRange: TimeRange(start: 1.2, end: 1.3),
                    outputStart: 0.1
                )
            ]
        )

        #expect(try await asset.load(.duration).seconds > 0.19)
        #expect(try await asset.load(.duration).seconds < 0.21)
        #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
    }

    private func fixtureURL(_ fileName: String) throws -> URL {
        try sharedFixtureURL(fileName)
    }
}
