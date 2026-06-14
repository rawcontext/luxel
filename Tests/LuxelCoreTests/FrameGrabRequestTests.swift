import Foundation
import LuxelCore
import Testing

@Suite("Frame grab request")
struct FrameGrabRequestTests {
    @Test("request stores source time crop and format")
    func requestStoresSourceTimeCropAndFormat() throws {
        let cropRect = try CaptureRect(x: 10, y: 20, width: 320, height: 180)
        let request = try FrameGrabRequest(
            sourceFileURL: URL(fileURLWithPath: "/tmp/luxel.mp4"),
            time: 1.25,
            cropRect: cropRect,
            format: .jpeg
        )

        #expect(request.sourceFileURL == URL(fileURLWithPath: "/tmp/luxel.mp4"))
        #expect(request.time == 1.25)
        #expect(request.cropRect == cropRect)
        #expect(request.format == .jpeg)
    }

    @Test("request rejects negative and non-finite times")
    func requestRejectsInvalidTimes() {
        #expect(throws: ScreenshotModelError.invalidFrameTime) {
            _ = try FrameGrabRequest(sourceFileURL: URL(fileURLWithPath: "/tmp/luxel.mp4"), time: -0.1)
        }
        #expect(throws: ScreenshotModelError.invalidFrameTime) {
            _ = try FrameGrabRequest(sourceFileURL: URL(fileURLWithPath: "/tmp/luxel.mp4"), time: .infinity)
        }
    }
}
