import CoreGraphics
import CoreMedia
import LuxelCore
import ScreenCaptureKit
import Testing

@Suite("ScreenCaptureKit recording configuration")
struct ScreenRecordingConfigurationFactoryTests {
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

        let configuration = ScreenRecordingConfigurationFactory()
            .makeStreamConfiguration(for: request)

        #expect(configuration.width == 642)
        #expect(configuration.height == 840)
        #expect(configuration.minimumFrameInterval == CMTime(value: 1, timescale: 60))
        #expect(!configuration.showsCursor)
        #expect(configuration.showMouseClicks)
        #expect(configuration.capturesAudio)
        #expect(configuration.captureMicrophone)
        #expect(configuration.microphoneCaptureDeviceID == "mic-1")
        #expect(configuration.excludesCurrentProcessAudio)
        #expect(configuration.sampleRate == 48_000)
        #expect(configuration.channelCount == 2)
        #expect(configuration.presenterOverlayPrivacyAlertSetting == .system)
        #expect(configuration.queueDepth == 8)
        #expect(configuration.sourceRect == CGRect(x: 42, y: 24, width: 641, height: 839))
    }
}
