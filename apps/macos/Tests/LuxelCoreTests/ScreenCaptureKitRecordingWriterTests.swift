import AVFoundation
import Foundation
import Testing

@testable import LuxelCore

@Suite("ScreenCaptureKit recording writer")
struct ScreenCaptureKitRecordingWriterTests {
    @Test("writer tells the encoder about high source frame rates")
    func writerUsesExpectedSourceFrameRate() throws {
        let request = try RecordingRequest(
            target: .display(DisplayID(12)),
            outputFileURL: URL(fileURLWithPath: "/tmp/luxel.mp4"),
            pixelSize: PixelSize(width: 1920, height: 1080),
            frameRate: FrameRate(120)
        )

        let settings = ScreenCaptureKitRecordingVideoSettings.outputSettings(for: request)
        let compression = try #require(
            settings[AVVideoCompressionPropertiesKey] as? [String: Any])

        #expect(compression[AVVideoExpectedSourceFrameRateKey] as? Int == 120)
    }
}
