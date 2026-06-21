import Foundation
import LuxelCore
import Testing

@Suite("Frame grab request")
struct FrameGrabRequestTests {
    @Test("request stores source time and crop")
    func requestStoresSourceTimeAndCrop() throws {
        let cropRect = try CaptureRect(x: 10, y: 20, width: 320, height: 180)
        let request = try FrameGrabRequest(
            sourceFileURL: URL(fileURLWithPath: "/tmp/luxel.mp4"),
            time: 1.25,
            cropRect: cropRect
        )

        #expect(request.sourceFileURL == URL(fileURLWithPath: "/tmp/luxel.mp4"))
        #expect(request.time == 1.25)
        #expect(request.cropRect == cropRect)
    }

    @Test("request rejects negative and non-finite times")
    func requestRejectsInvalidTimes() {
        #expect(throws: FrameGrabError.invalidFrameTime) {
            _ = try FrameGrabRequest(sourceFileURL: URL(fileURLWithPath: "/tmp/luxel.mp4"), time: -0.1)
        }
        #expect(throws: FrameGrabError.invalidFrameTime) {
            _ = try FrameGrabRequest(
                sourceFileURL: URL(fileURLWithPath: "/tmp/luxel.mp4"), time: .infinity)
        }
    }

    @Test("request suggests source frame file name")
    func requestSuggestsSourceFrameFileName() throws {
        let request = try FrameGrabRequest(
            sourceFileURL: URL(fileURLWithPath: "/tmp/Luxel 2026-06-12 at 10.15.30.mp4"),
            time: 4.29
        )

        #expect(request.suggestedFileName == "Luxel 2026-06-12 at 10.15.30 (frame 0.04.2).png")
    }

    @Test("request frame file name uses minutes")
    func requestFrameFileNameUsesMinutes() throws {
        let request = try FrameGrabRequest(
            sourceFileURL: URL(fileURLWithPath: "/tmp/Tutorial.mov"),
            time: 64.38
        )

        #expect(request.suggestedFileName == "Tutorial (frame 1.04.3).png")
    }
}
