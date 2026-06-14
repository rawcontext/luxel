import CoreGraphics
import ImageIO
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

    @Test("GIF bitmap rendering preserves alpha or applies matte")
    func gifBitmapRenderingPreservesAlphaOrAppliesMatte() throws {
        let image = try transparentRedImage()
        let transparentBitmap = try AnimatedFrameRenderer().renderGIFBitmap(
            image,
            outputPixelSize: PixelSize(width: 2, height: 1),
            shouldCrop: true
        )
        let mattedBitmap = try AnimatedFrameRenderer().renderGIFBitmap(
            image,
            outputPixelSize: PixelSize(width: 2, height: 1),
            shouldCrop: true,
            backgroundMatte: RGBColor(red: 1, green: 1, blue: 1)
        )

        #expect(transparentBitmap.pixels[0].alpha == 0)
        #expect(transparentBitmap.pixels[1].red == 255)
        #expect(transparentBitmap.pixels[1].alpha == 255)
        #expect(mattedBitmap.pixels[0] == GIFRGBAPixel(red: 255, green: 255, blue: 255))
        #expect(mattedBitmap.pixels[1].red == 255)
        #expect(mattedBitmap.pixels[1].alpha == 255)
    }

    @Test("image rendering preserves source alpha for APNG frames")
    func imageRenderingPreservesSourceAlphaForAPNGFrames() throws {
        let image = try transparentRedImage()
        let renderedImage = try AnimatedFrameRenderer().renderImage(
            image,
            outputPixelSize: PixelSize(width: 2, height: 1),
            shouldCrop: true
        )
        let pixels = try rgbaPixels(from: renderedImage)

        #expect(pixels[0].alpha == 0)
        #expect(pixels[1].red == 255)
        #expect(pixels[1].alpha == 255)
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

    private func transparentRedImage() throws -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let context = try #require(CGContext(
            data: nil,
            width: 2,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))

        context.clear(CGRect(x: 0, y: 0, width: 2, height: 1))
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 1, y: 0, width: 1, height: 1))

        return try #require(context.makeImage())
    }

    private func rgbaPixels(from image: CGImage) throws -> [GIFRGBAPixel] {
        let bytesPerPixel = 4
        let bytesPerRow = image.width * bytesPerPixel
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        var bytes = Array(repeating: UInt8(0), count: image.height * bytesPerRow)

        try bytes.withUnsafeMutableBytes { pointer in
            let context = try #require(CGContext(
                data: pointer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ))
            context.clear(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }

        return stride(from: 0, to: bytes.count, by: bytesPerPixel).map { offset in
            GIFRGBAPixel(
                red: bytes[offset],
                green: bytes[offset + 1],
                blue: bytes[offset + 2],
                alpha: bytes[offset + 3]
            )
        }
    }
}

@Suite("Native GIF encoder")
struct NativeGIFEncoderTests {
    @Test("encoder maps source alpha to the GIF transparent index")
    func encoderMapsSourceAlphaToTheGIFTransparentIndex() throws {
        let pixelSize = try PixelSize(width: 2, height: 1)
        let frame = try GIFFrameBitmap(
            pixelSize: pixelSize,
            pixels: [
                GIFRGBAPixel(red: 255, green: 0, blue: 0, alpha: 0),
                GIFRGBAPixel(red: 255, green: 0, blue: 0, alpha: 255)
            ]
        )

        let data = try NativeGIFEncoder().data(
            pixelSize: pixelSize,
            frames: [frame],
            frameDelay: 0.1,
            options: GIFRenderOptions(dithering: .none)
        )
        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let pixels = try rgbaPixels(from: decoded)

        #expect(pixels[0].alpha == 0)
        #expect(pixels[1].red > pixels[1].green)
        #expect(pixels[1].red > pixels[1].blue)
        #expect(pixels[1].alpha == 255)
    }

    private func rgbaPixels(from image: CGImage) throws -> [GIFRGBAPixel] {
        let bytesPerPixel = 4
        let bytesPerRow = image.width * bytesPerPixel
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        var bytes = Array(repeating: UInt8(0), count: image.height * bytesPerRow)

        try bytes.withUnsafeMutableBytes { pointer in
            let context = try #require(CGContext(
                data: pointer.baseAddress,
                width: image.width,
                height: image.height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ))
            context.clear(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }

        return stride(from: 0, to: bytes.count, by: bytesPerPixel).map { offset in
            GIFRGBAPixel(
                red: bytes[offset],
                green: bytes[offset + 1],
                blue: bytes[offset + 2],
                alpha: bytes[offset + 3]
            )
        }
    }
}
