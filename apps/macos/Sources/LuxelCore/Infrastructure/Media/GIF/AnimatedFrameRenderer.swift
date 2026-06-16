import CoreGraphics
import Foundation

struct AnimatedFrameRenderer: Sendable {
    func renderImage(
        _ image: CGImage,
        outputPixelSize: PixelSize,
        shouldCrop: Bool,
        sourceCropRect: CaptureRect? = nil,
        cameraTransform: CameraTransform = .identity
    ) throws -> CGImage {
        let drawableImage = try drawableFrame(
            for: image,
            sourceCropRect: sourceCropRect,
            cameraTransform: cameraTransform
        )
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

        context.clear(CGRect(origin: .zero, size: outputSize))
        context.interpolationQuality = .high
        context.draw(drawableImage, in: drawRect(for: drawableImage, outputSize: outputSize, shouldCrop: shouldCrop))

        guard let renderedImage = context.makeImage() else {
            throw AnimatedFrameRendererError.cannotRenderFrame
        }

        return renderedImage
    }

    func renderGIFBitmap(
        _ image: CGImage,
        outputPixelSize: PixelSize,
        shouldCrop: Bool,
        sourceCropRect: CaptureRect? = nil,
        backgroundMatte: RGBColor? = nil,
        cameraTransform: CameraTransform = .identity
    ) throws -> GIFFrameBitmap {
        let drawableImage = try drawableFrame(
            for: image,
            sourceCropRect: sourceCropRect,
            cameraTransform: cameraTransform
        )
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

            context.setFillColor(Self.backgroundFillColor(backgroundMatte))
            context.fill(CGRect(origin: .zero, size: outputSize))
            context.interpolationQuality = .high
            context.draw(
                drawableImage,
                in: drawRect(for: drawableImage, outputSize: outputSize, shouldCrop: shouldCrop)
            )
        }

        var pixels: [GIFRGBAPixel] = []
        pixels.reserveCapacity(outputPixelSize.width * outputPixelSize.height)
        for offset in stride(from: 0, to: bytes.count, by: bytesPerPixel) {
            let alpha = bytes[offset + 3]
            pixels.append(GIFRGBAPixel(
                red: Self.unpremultipliedComponent(bytes[offset], alpha: alpha),
                green: Self.unpremultipliedComponent(bytes[offset + 1], alpha: alpha),
                blue: Self.unpremultipliedComponent(bytes[offset + 2], alpha: alpha),
                alpha: alpha
            ))
        }

        return try GIFFrameBitmap(pixelSize: outputPixelSize, pixels: pixels)
    }

    private static func backgroundFillColor(_ matte: RGBColor?) -> CGColor {
        guard let matte else {
            return CGColor(gray: 0, alpha: 0)
        }

        return CGColor(red: matte.red, green: matte.green, blue: matte.blue, alpha: 1)
    }

    private static func unpremultipliedComponent(_ component: UInt8, alpha: UInt8) -> UInt8 {
        guard alpha > 0, alpha < 255 else {
            return component
        }

        return UInt8(min(255, (Int(component) * 255 + Int(alpha) / 2) / Int(alpha)))
    }

    private func drawableFrame(
        for image: CGImage,
        sourceCropRect: CaptureRect?,
        cameraTransform: CameraTransform
    ) throws -> CGImage {
        let sourceImage = try sourceFrame(for: image, cropRect: sourceCropRect)
        return try cameraFrame(for: sourceImage, cameraTransform: cameraTransform)
    }

    private func sourceFrame(for image: CGImage, cropRect: CaptureRect?) throws -> CGImage {
        guard let cropRect else {
            return image
        }

        let imageRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let requestedRect = CGRect(
            x: cropRect.originX,
            y: cropRect.originY,
            width: cropRect.width,
            height: cropRect.height
        )
        let clampedRect = requestedRect.intersection(imageRect).integral
        guard !clampedRect.isNull,
              clampedRect.width > 0,
              clampedRect.height > 0,
              let croppedImage = image.cropping(to: clampedRect) else {
            throw AnimatedFrameRendererError.cannotCropFrame
        }

        return croppedImage
    }

    private func cameraFrame(for image: CGImage, cameraTransform: CameraTransform) throws -> CGImage {
        guard cameraTransform != .identity else {
            return image
        }

        let cropRect = pixelCropRect(for: image, sourceRect: cameraTransform.sourceRect)
        guard let croppedImage = image.cropping(to: cropRect) else {
            throw AnimatedFrameRendererError.cannotCropFrame
        }

        return croppedImage
    }

    private func pixelCropRect(for image: CGImage, sourceRect: NormalizedRect) -> CGRect {
        let imageRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let minX = (sourceRect.originX * Double(image.width)).rounded(.down)
        let minY = (sourceRect.originY * Double(image.height)).rounded(.down)
        let maxX = ((sourceRect.originX + sourceRect.width) * Double(image.width)).rounded(.up)
        let maxY = ((sourceRect.originY + sourceRect.height) * Double(image.height)).rounded(.up)

        return CGRect(
            x: minX,
            y: minY,
            width: max(1, maxX - minX),
            height: max(1, maxY - minY)
        )
        .intersection(imageRect)
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
    case cannotCropFrame
    case cannotRenderFrame
}
