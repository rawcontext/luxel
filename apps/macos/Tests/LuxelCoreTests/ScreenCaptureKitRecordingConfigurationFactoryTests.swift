import CoreGraphics
import CoreMedia
import CoreVideo
import ScreenCaptureKit
import Testing
@testable import LuxelCore

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
            .makeStreamConfiguration(for: request, pointPixelScale: 2)

        #expect(configuration.width == 642)
        #expect(configuration.height == 840)
        #expect(configuration.minimumFrameInterval == CMTime(value: 1, timescale: 60))
        #expect(!configuration.showsCursor)
        #expect(configuration.showMouseClicks)
        #expect(configuration.pixelFormat == kCVPixelFormatType_32BGRA)
        #expect(configuration.capturesAudio)
        #expect(configuration.captureMicrophone)
        #expect(configuration.microphoneCaptureDeviceID == "mic-1")
        #expect(configuration.excludesCurrentProcessAudio)
        #expect(configuration.sampleRate == 48_000)
        #expect(configuration.channelCount == 2)
        #expect(configuration.presenterOverlayPrivacyAlertSetting == .system)
        #expect(configuration.queueDepth == 8)
        #expect(configuration.sourceRect == CGRect(x: 21, y: 12, width: 320.5, height: 419.5))
    }

    @Test("window request resolves point content rect to native pixels")
    func windowRequestResolvesPointContentRectToNativePixels() throws {
        let request = try RecordingRequest(
            target: .window(id: 42),
            outputFileURL: URL(fileURLWithPath: "/tmp/luxel.mp4"),
            pixelSize: PixelSize(width: 640, height: 360),
            frameRate: FrameRate(30)
        )

        let resolvedRequest = ScreenRecordingConfigurationFactory()
            .requestByResolvingCaptureGeometry(
                request,
                contentRect: CGRect(x: 0, y: 0, width: 640, height: 360),
                pointPixelScale: 2
            )

        #expect(resolvedRequest.pixelSize == (try PixelSize(width: 1280, height: 720)))
        #expect(resolvedRequest.target == request.target)
        #expect(resolvedRequest.outputFileURL == request.outputFileURL)
    }

    @Test("window configuration scales independent window into output frame")
    func windowConfigurationScalesIndependentWindowIntoOutputFrame() throws {
        let request = try RecordingRequest(
            target: .window(id: 42),
            outputFileURL: URL(fileURLWithPath: "/tmp/luxel.mp4"),
            pixelSize: PixelSize(width: 1280, height: 720),
            frameRate: FrameRate(30)
        )

        let configuration = ScreenRecordingConfigurationFactory()
            .makeStreamConfiguration(for: request)

        #expect(configuration.scalesToFit)
        #expect(configuration.width == 1280)
        #expect(configuration.height == 720)
    }
}
