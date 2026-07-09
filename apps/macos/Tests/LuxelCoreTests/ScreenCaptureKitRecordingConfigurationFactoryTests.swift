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
        #expect(configuration.sourceRect == CGRect(x: 42, y: 24, width: 641, height: 839))
    }

    @Test("120 FPS capture uses an encoding-efficient pixel format")
    func highFrameRateCaptureUsesEncodingPixelFormat() throws {
        let request = try RecordingRequest(
            target: .display(DisplayID(12)),
            outputFileURL: URL(fileURLWithPath: "/tmp/luxel.mp4"),
            pixelSize: PixelSize(width: 1920, height: 1080),
            frameRate: FrameRate(120)
        )

        let configuration = ScreenRecordingConfigurationFactory()
            .makeStreamConfiguration(for: request)

        #expect(configuration.minimumFrameInterval == CMTime(value: 1, timescale: 120))
        #expect(configuration.pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
    }

    @Test("matching the display uses the maximum supported capture cadence")
    func matchingDisplayUsesMaximumCaptureCadence() throws {
        let request = try RecordingRequest(
            target: .display(DisplayID(12)),
            outputFileURL: URL(fileURLWithPath: "/tmp/luxel.mp4"),
            pixelSize: PixelSize(width: 1920, height: 1080),
            frameRate: .fps120,
            matchesDisplayFrameRate: true
        )

        let configuration = ScreenRecordingConfigurationFactory()
            .makeStreamConfiguration(for: request)

        #expect(configuration.minimumFrameInterval == .zero)
        #expect(configuration.pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
    }

    @Test("top area selection maps to top source rect")
    func topAreaSelectionMapsToTopSourceRect() throws {
        let display = try DisplayBounds(id: DisplayID(12), x: 0, y: 0, width: 1728, height: 1117)
        let draft = try CaptureSelectionDraft(
            display: display,
            topLeftSelection: CaptureRect(x: 888, y: 0, width: 840, height: 84)
        )
        let request = try RecordingRequest(
            target: draft.captureTarget,
            outputFileURL: URL(fileURLWithPath: "/tmp/luxel.mp4"),
            pixelSize: draft.pixelSize,
            frameRate: FrameRate(30)
        )

        let configuration = ScreenRecordingConfigurationFactory()
            .makeStreamConfiguration(for: request, pointPixelScale: 2)

        #expect(configuration.width == 840)
        #expect(configuration.height == 84)
        #expect(configuration.sourceRect == CGRect(x: 888, y: 0, width: 840, height: 84))
    }

    @Test("area request resolves point selection to native pixels")
    func areaRequestResolvesPointSelectionToNativePixels() throws {
        let rect = try CaptureRect(x: 444, y: 120, width: 418, height: 248)
        let request = try RecordingRequest(
            target: .area(displayID: DisplayID(12), rect: rect),
            outputFileURL: URL(fileURLWithPath: "/tmp/luxel.mp4"),
            pixelSize: PixelSize(width: 418, height: 248),
            frameRate: FrameRate(30)
        )

        let resolvedRequest = ScreenRecordingConfigurationFactory()
            .requestByResolvingCaptureGeometry(
                request,
                contentRect: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                pointPixelScale: 2
            )

        #expect(resolvedRequest.pixelSize == (try PixelSize(width: 836, height: 496)))
        #expect(resolvedRequest.target == request.target)
    }

    @Test("display request resolves point content rect to native pixels")
    func displayRequestResolvesPointContentRectToNativePixels() throws {
        let request = try RecordingRequest(
            target: .display(DisplayID(42)),
            outputFileURL: URL(fileURLWithPath: "/tmp/luxel.mp4"),
            pixelSize: PixelSize(width: 1728, height: 1117),
            frameRate: FrameRate(30)
        )

        let resolvedRequest = ScreenRecordingConfigurationFactory()
            .requestByResolvingCaptureGeometry(
                request,
                contentRect: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                pointPixelScale: 2
            )

        #expect(resolvedRequest.pixelSize == (try PixelSize(width: 3456, height: 2234)))
        #expect(resolvedRequest.target == request.target)
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
