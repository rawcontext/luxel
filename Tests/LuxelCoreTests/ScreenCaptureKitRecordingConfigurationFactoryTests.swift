import AVFoundation
import CoreGraphics
import CoreMedia
import LuxelCore
import ScreenCaptureKit
import Testing

@Suite("ScreenCaptureKit recording configuration")
struct ScreenCaptureKitRecordingConfigurationFactoryTests {
    @Test("stream configuration maps domain capture settings")
    func streamConfigurationMapsDomainCaptureSettings() throws {
        let rect = try CaptureRect(x: 42, y: 24, width: 641, height: 839)
        let request = try RecordingRequest(
            target: .area(displayID: DisplayID(12), rect: rect),
            outputFileURL: URL(fileURLWithPath: "/tmp/luxel.mp4"),
            pixelSize: PixelSize(width: 641, height: 839),
            frameRate: FrameRate(60),
            showCursor: false,
            highlightClicks: true,
            audio: .systemAndMicrophone(deviceID: "mic-1"),
            videoCodec: .hevc
        )

        let configuration = ScreenCaptureKitRecordingConfigurationFactory()
            .makeStreamConfiguration(for: request)

        #expect(configuration.width == 641)
        #expect(configuration.height == 839)
        #expect(configuration.minimumFrameInterval == CMTime(value: 1, timescale: 60))
        #expect(!configuration.showsCursor)
        #expect(configuration.showMouseClicks)
        #expect(configuration.capturesAudio)
        #expect(configuration.captureMicrophone)
        #expect(configuration.microphoneCaptureDeviceID == "mic-1")
        #expect(configuration.excludesCurrentProcessAudio)
        #expect(configuration.queueDepth == 8)
        #expect(configuration.sourceRect == CGRect(x: 42, y: 24, width: 641, height: 839))
    }

    @Test("recording output configuration maps file and codec settings")
    func recordingOutputConfigurationMapsFileAndCodecSettings() throws {
        let outputURL = URL(fileURLWithPath: "/tmp/luxel.mp4")
        let request = try RecordingRequest(
            target: .display(DisplayID(12)),
            outputFileURL: outputURL,
            pixelSize: PixelSize(width: 1280, height: 720),
            frameRate: FrameRate(30),
            videoCodec: .hevc
        )

        let configuration = ScreenCaptureKitRecordingConfigurationFactory()
            .makeRecordingOutputConfiguration(for: request)

        #expect(configuration.outputURL == outputURL)
        #expect(configuration.outputFileType == .mp4)
        #expect(configuration.videoCodecType == .hevc)
    }
}
