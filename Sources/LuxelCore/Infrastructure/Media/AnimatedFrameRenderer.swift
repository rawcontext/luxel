import CoreGraphics
import Foundation

struct AnimatedFrameRenderer: Sendable {
    func renderImage(
        _ image: CGImage,
        outputPixelSize: PixelSize,
        shouldCrop: Bool
    ) throws -> CGImage {
        let outputSize = CGSize(width: outputPixelSize.width, height: outputPixelSize.height)
        guard let context = CGContext(
            data: nil,
            width: outputPixelSize.width,
            height: outputPixelSize.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw AnimatedFrameRendererError.cannotCreateFrameContext
        }

        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: outputSize))
        context.interpolationQuality = .high
        context.draw(image, in: drawRect(for: image, outputSize: outputSize, shouldCrop: shouldCrop))

        guard let renderedImage = context.makeImage() else {
            throw AnimatedFrameRendererError.cannotRenderFrame
        }

        return renderedImage
    }

    func renderGIFBitmap(
        _ image: CGImage,
        outputPixelSize: PixelSize,
        shouldCrop: Bool
    ) throws -> GIFFrameBitmap {
        let bytesPerPixel = 4
        let bytesPerRow = outputPixelSize.width * bytesPerPixel
        let outputSize = CGSize(width: outputPixelSize.width, height: outputPixelSize.height)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
        var bytes = Array(
            repeating: UInt8(0),
            count: outputPixelSize.height * bytesPerRow
        )

        try bytes.withUnsafeMutableBytes { pointer in
            guard let context = CGContext(
                data: pointer.baseAddress,
                width: outputPixelSize.width,
                height: outputPixelSize.height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else {
                throw AnimatedFrameRendererError.cannotCreateFrameContext
            }

            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(CGRect(origin: .zero, size: outputSize))
            context.interpolationQuality = .high
            context.draw(image, in: drawRect(for: image, outputSize: outputSize, shouldCrop: shouldCrop))
        }

        var pixels: [GIFRGBAPixel] = []
        pixels.reserveCapacity(outputPixelSize.width * outputPixelSize.height)
        for offset in stride(from: 0, to: bytes.count, by: bytesPerPixel) {
            pixels.append(GIFRGBAPixel(
                red: bytes[offset],
                green: bytes[offset + 1],
                blue: bytes[offset + 2],
                alpha: bytes[offset + 3]
            ))
        }

        return try GIFFrameBitmap(pixelSize: outputPixelSize, pixels: pixels)
    }

    private func drawRect(
        for image: CGImage,
        outputSize: CGSize,
        shouldCrop: Bool
    ) -> CGRect {
        let inputSize = CGSize(width: image.width, height: image.height)
        let widthScale = outputSize.width / inputSize.width
        let heightScale = outputSize.height / inputSize.height
        let scale = shouldCrop ? max(widthScale, heightScale) : min(widthScale, heightScale)
        let scaledSize = CGSize(width: inputSize.width * scale, height: inputSize.height * scale)

        return CGRect(
            x: (outputSize.width - scaledSize.width) / 2,
            y: (outputSize.height - scaledSize.height) / 2,
            width: scaledSize.width,
            height: scaledSize.height
        )
    }
}

enum AnimatedFrameRendererError: Error, Equatable {
    case cannotCreateFrameContext
    case cannotRenderFrame
}
