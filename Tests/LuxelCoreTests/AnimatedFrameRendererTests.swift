import CoreGraphics
@testable import LuxelCore
import Testing

@Suite("Animated frame renderer")
struct AnimatedFrameRendererTests {
    @Test("camera transform crops before output scaling")
    func cameraTransformCropsBeforeOutputScaling() throws {
        let image = try splitColorImage(width: 4, height: 2)
        let cameraTransform = try CameraTransform(
            scale: 2,
            sourceRect: NormalizedRect(x: 0, y: 0, width: 0.5, height: 1)
        )

        let bitmap = try AnimatedFrameRenderer().renderGIFBitmap(
            image,
            outputPixelSize: PixelSize(width: 2, height: 2),
            shouldCrop: false,
            cameraTransform: cameraTransform
        )

        #expect(bitmap.pixels.allSatisfy { pixel in
            pixel.red > pixel.blue && pixel.red > pixel.green && pixel.alpha > 0
        })
    }

    private func splitColorImage(width: Int, height: Int) throws -> CGImage {
        let outputSize = CGSize(width: width, height: height)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))

        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: outputSize.width / 2, height: outputSize.height))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: outputSize.width / 2, y: 0, width: outputSize.width / 2, height: outputSize.height))

        return try #require(context.makeImage())
    }
}
