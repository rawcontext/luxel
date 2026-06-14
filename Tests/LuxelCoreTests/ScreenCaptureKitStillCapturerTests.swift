import CoreGraphics
import CoreVideo
import ImageIO
import LuxelCore
import ScreenCaptureKit
import Testing

@Suite("ScreenCaptureKit still capturer")
struct ScreenCaptureKitStillCapturerTests {
    @Test("configuration maps area source rect and native scale")
    func configurationMapsAreaSourceRectAndNativeScale() throws {
        let request = try ScreenshotRequest(
            target: .area(displayID: DisplayID(42), rect: CaptureRect(x: 10, y: 20, width: 320, height: 180)),
            includeCursor: false,
            scale: .native,
            format: .png
        )

        let configuration = try ScreenCaptureKitStillConfigurationFactory()
            .makeConfiguration(
                for: request,
                contentRect: CGRect(x: 0, y: 0, width: 1440, height: 900),
                pointPixelScale: 2
            )

        #expect(!configuration.showsCursor)
        #expect(configuration.width == 640)
        #expect(configuration.height == 360)
        #expect(configuration.sourceRect == CGRect(x: 10, y: 20, width: 320, height: 180))
    }

    @Test("configuration can request point scale output")
    func configurationCanRequestPointScaleOutput() throws {
        let request = try ScreenshotRequest(
            target: .display(DisplayID(42)),
            includeCursor: true,
            scale: .points,
            format: .png
        )

        let configuration = try ScreenCaptureKitStillConfigurationFactory()
            .makeConfiguration(
                for: request,
                contentRect: CGRect(x: 0, y: 0, width: 1440, height: 900),
                pointPixelScale: 2
            )

        #expect(configuration.showsCursor)
        #expect(configuration.width == 1440)
        #expect(configuration.height == 900)
    }

    @Test("transparent window configuration requests alpha pixels without shadows")
    func transparentWindowConfigurationRequestsAlphaPixelsWithoutShadows() throws {
        let request = try ScreenshotRequest(
            target: .window(id: 42),
            includeCursor: false,
            scale: .native,
            format: .png,
            backdrop: .transparent
        )

        let configuration = try ScreenCaptureKitStillConfigurationFactory()
            .makeConfiguration(
                for: request,
                contentRect: CGRect(x: 0, y: 0, width: 640, height: 360),
                pointPixelScale: 2
            )

        #expect(configuration.backgroundColor.alpha == 0)
        #expect(configuration.pixelFormat == kCVPixelFormatType_32BGRA)
        #expect(configuration.ignoreShadowsSingleWindow)
    }

    @Test("transparent shadow window configuration preserves shadows")
    func transparentShadowWindowConfigurationPreservesShadows() throws {
        let request = try ScreenshotRequest(
            target: .window(id: 42),
            includeCursor: false,
            scale: .native,
            format: .png,
            backdrop: .transparentWithShadow
        )

        let configuration = try ScreenCaptureKitStillConfigurationFactory()
            .makeConfiguration(
                for: request,
                contentRect: CGRect(x: 0, y: 0, width: 640, height: 360),
                pointPixelScale: 2
            )

        #expect(configuration.backgroundColor.alpha == 0)
        #expect(configuration.pixelFormat == kCVPixelFormatType_32BGRA)
        #expect(!configuration.ignoreShadowsSingleWindow)
    }

    @Test("ImageIO encoder writes readable PNG data")
    func imageIOEncoderWritesReadablePNGData() throws {
        let image = try makeImage(width: 2, height: 1)

        let data = try ImageIOStillImageEncoder().encode(image, format: .png)

        let source = CGImageSourceCreateWithData(data as CFData, nil)
        #expect(source != nil)
        #expect(source.map(CGImageSourceGetCount) == 1)
        #expect(data.starts(with: [0x89, 0x50, 0x4e, 0x47]))
    }

    @Test("ImageIO encoder writes readable JPEG data")
    func imageIOEncoderWritesReadableJPEGData() throws {
        let image = try makeImage(width: 2, height: 1)

        let data = try ImageIOStillImageEncoder().encode(image, format: .jpeg)

        let source = CGImageSourceCreateWithData(data as CFData, nil)
        #expect(source != nil)
        #expect(source.map(CGImageSourceGetCount) == 1)
        #expect(data.starts(with: [0xff, 0xd8]))
    }

    private func makeImage(width: Int, height: Int) throws -> CGImage {
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let pixels = Data(repeating: 0xff, count: height * bytesPerRow)
        let provider = CGDataProvider(data: pixels as CFData)
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let provider,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bitsPerPixel: 32,
                  bytesPerRow: bytesPerRow,
                  space: colorSpace,
                  bitmapInfo: bitmapInfo,
                  provider: provider,
                  decode: nil,
                  shouldInterpolate: false,
                  intent: .defaultIntent
              ) else {
            throw ScreenCaptureKitStillCapturerError.encodingFailed(.png)
        }

        return image
    }
}
