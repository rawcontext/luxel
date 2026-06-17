import Foundation
import ImageIO
import LuxelCore
import Testing

@Suite("AVFoundation frame grabber")
struct AVFoundationFrameGrabberTests {
    @Test("grab extracts a PNG frame from a movie")
    func grabExtractsPNGFrameFromMovie() async throws {
        let request = try FrameGrabRequest(
            sourceFileURL: fixtureURL("input.mp4"),
            time: 1,
            format: .png
        )

        let imageData = try await AVFoundationFrameGrabber().grab(request)
        let expectedPixelSize = try PixelSize(width: 2560, height: 1440)

        #expect(imageData.format == .png)
        #expect(imageData.pixelSize == expectedPixelSize)
        #expect(imageData.data.starts(with: [0x89, 0x50, 0x4e, 0x47]))
        #expect(CGImageSourceCreateWithData(imageData.data as CFData, nil).map(CGImageSourceGetCount) == 1)
    }

    @Test("grab crops a frame before encoding")
    func grabCropsFrameBeforeEncoding() async throws {
        let cropRect = try CaptureRect(x: 0, y: 0, width: 320, height: 180)
        let request = try FrameGrabRequest(
            sourceFileURL: fixtureURL("input.mp4"),
            time: 1,
            cropRect: cropRect
        )

        let imageData = try await AVFoundationFrameGrabber().grab(request)
        let expectedPixelSize = try PixelSize(width: 320, height: 180)

        #expect(imageData.pixelSize == expectedPixelSize)
    }

    @Test("grab rejects crops outside the generated frame")
    func grabRejectsCropsOutsideGeneratedFrame() async throws {
        let cropRect = try CaptureRect(x: 2_500, y: 1_400, width: 320, height: 180)
        let request = try FrameGrabRequest(
            sourceFileURL: fixtureURL("input.mp4"),
            time: 1,
            cropRect: cropRect
        )

        await #expect(throws: AVFoundationFrameGrabberError.cropOutsideFrame) {
            _ = try await AVFoundationFrameGrabber().grab(request)
        }
    }

    private func fixtureURL(_ fileName: String) throws -> URL {
        try packageRootURL()
            .appending(path: "Tests/Fixtures")
            .appending(path: fileName)
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
