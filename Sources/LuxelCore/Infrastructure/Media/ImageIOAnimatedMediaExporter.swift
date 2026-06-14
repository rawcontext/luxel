import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ImageIOAnimatedMediaExporter: MediaExporter, Sendable {
    public init() {}

    public func export(_ request: ExportRequest, to outputFileURL: URL) async throws -> ExportedMedia {
        guard request.format == .gif || request.format == .apng else {
            throw ImageIOAnimatedMediaExporterError.unsupportedFormat(request.format)
        }

        let outputPixelSize = try request.outputPixelSize
        let asset = AVURLAsset(url: request.inputFileURL)
        let schedule = await animatedFrameSchedule(for: request, asset: asset)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero

        if request.format == .gif {
            try await exportGIF(
                request,
                to: outputFileURL,
                outputPixelSize: outputPixelSize,
                schedule: schedule,
                imageGenerator: imageGenerator
            )
            return ExportedMedia(
                fileURL: outputFileURL,
                format: request.format,
                pixelSize: outputPixelSize,
                shouldMute: request.outputShouldMute
            )
        }

        let destination = try makeDestination(
            format: request.format,
            outputFileURL: outputFileURL,
            frameCount: schedule.frameTimes.count
        )
        let destinationProperties = destinationProperties(for: request.format)
        CGImageDestinationSetProperties(destination, destinationProperties as CFDictionary)

        try? FileManager.default.removeItem(at: outputFileURL)

        do {
            for time in schedule.frameTimes {
                let frame = try await imageGenerator.image(at: time).image
                let renderedFrame = try render(
                    frame,
                    outputPixelSize: outputPixelSize,
                    shouldCrop: request.shouldCrop
                )
                CGImageDestinationAddImage(
                    destination,
                    renderedFrame,
                    frameProperties(for: request.format, frameDelay: schedule.frameDelay) as CFDictionary
                )
            }

            guard CGImageDestinationFinalize(destination) else {
                throw ImageIOAnimatedMediaExporterError.finalizeFailed
            }
        } catch {
            try? FileManager.default.removeItem(at: outputFileURL)
            throw error
        }

        return ExportedMedia(
            fileURL: outputFileURL,
            format: request.format,
            pixelSize: outputPixelSize,
            shouldMute: request.outputShouldMute
        )
    }

    private func exportGIF(
        _ request: ExportRequest,
        to outputFileURL: URL,
        outputPixelSize: PixelSize,
        schedule: AnimatedFrameSchedule,
        imageGenerator: AVAssetImageGenerator
    ) async throws {
        let options: GIFRenderOptions
        if let gifOptions = request.gifOptions {
            options = gifOptions
        } else {
            options = try GIFRenderOptions(quality: request.resolvedQuality)
        }

        let baseFrames = try await renderedBitmaps(
            for: schedule,
            outputPixelSize: outputPixelSize,
            shouldCrop: request.shouldCrop,
            imageGenerator: imageGenerator
        )
        let frameIndexes = try GIFFrameSequencePlanner()
            .frameIndexes(frameCount: baseFrames.count, loopMode: options.loopMode)
        let frames = frameIndexes.map { baseFrames[$0] }
        let transparentColorIndex = UInt8(0)
        let sourcePalette = try MedianCutPaletteBuilder().palette(
            from: frames,
            maxColorCount: min(options.paletteSize, 255)
        )
        let palette = try GIFColorPalette(colors: [
            GIFPaletteColor(red: 0, green: 0, blue: 0)
        ] + sourcePalette.colors)
        let indexedFrames = try GIFFrameIndexer()
            .indexedFrames(
                from: frames,
                palette: sourcePalette,
                dithering: options.dithering
            )
            .map(shiftedIndexedFrame)
        let deltas = try frameDeltas(
            bitmaps: frames,
            indexedFrames: indexedFrames,
            transparentColorIndex: transparentColorIndex,
            lossyTolerance: options.lossyTolerance
        )
        let delays = try CentisecondDelayPlanner().plan(
            frameCount: frames.count,
            frameDuration: schedule.frameDelay
        )

        try? FileManager.default.removeItem(at: outputFileURL)
        do {
            try GIFContainerWriter().write(
                pixelSize: outputPixelSize,
                palette: palette,
                frames: deltas,
                delays: delays,
                loopMode: options.loopMode,
                to: outputFileURL
            )
        } catch {
            try? FileManager.default.removeItem(at: outputFileURL)
            throw error
        }
    }

    private func renderedBitmaps(
        for schedule: AnimatedFrameSchedule,
        outputPixelSize: PixelSize,
        shouldCrop: Bool,
        imageGenerator: AVAssetImageGenerator
    ) async throws -> [GIFFrameBitmap] {
        var frames: [GIFFrameBitmap] = []
        frames.reserveCapacity(schedule.frameTimes.count)

        for time in schedule.frameTimes {
            let frame = try await imageGenerator.image(at: time).image
            frames.append(try renderBitmap(
                frame,
                outputPixelSize: outputPixelSize,
                shouldCrop: shouldCrop
            ))
        }

        return frames
    }

    private func frameDeltas(
        bitmaps: [GIFFrameBitmap],
        indexedFrames: [GIFIndexedFrame],
        transparentColorIndex: UInt8,
        lossyTolerance: Int
    ) throws -> [GIFFrameDelta] {
        let differ = GIFFrameDiffer()
        var previousFrame: GIFFrameBitmap?
        var deltas: [GIFFrameDelta] = []
        deltas.reserveCapacity(bitmaps.count)

        for (bitmap, indexedFrame) in zip(bitmaps, indexedFrames) {
            deltas.append(try differ.delta(
                from: previousFrame,
                to: bitmap,
                indexedFrame: indexedFrame,
                transparentColorIndex: transparentColorIndex,
                lossyTolerance: lossyTolerance
            ))
            previousFrame = bitmap
        }

        return deltas
    }

    private func shiftedIndexedFrame(_ frame: GIFIndexedFrame) throws -> GIFIndexedFrame {
        try GIFIndexedFrame(
            pixelSize: frame.pixelSize,
            colorIndexes: frame.colorIndexes.map { $0 + 1 }
        )
    }

    private func makeDestination(
        format: ExportFormat,
        outputFileURL: URL,
        frameCount: Int
    ) throws -> CGImageDestination {
        let typeIdentifier: String
        switch format {
        case .gif:
            typeIdentifier = UTType.gif.identifier
        case .apng:
            typeIdentifier = UTType.png.identifier
        case .av1, .hevc, .mp4, .webm:
            throw ImageIOAnimatedMediaExporterError.unsupportedFormat(format)
        }

        guard let destination = CGImageDestinationCreateWithURL(
            outputFileURL as CFURL,
            typeIdentifier as CFString,
            frameCount,
            nil
        ) else {
            throw ImageIOAnimatedMediaExporterError.cannotCreateDestination
        }

        return destination
    }

    private func destinationProperties(for format: ExportFormat) -> [CFString: Any] {
        switch format {
        case .gif:
            [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFLoopCount: 0
                ]
            ]
        case .apng:
            [
                kCGImagePropertyPNGDictionary: [
                    kCGImagePropertyAPNGLoopCount: 0
                ]
            ]
        case .av1, .hevc, .mp4, .webm:
            [:]
        }
    }

    private func frameProperties(
        for format: ExportFormat,
        frameDelay: TimeInterval
    ) -> [CFString: Any] {
        switch format {
        case .gif:
            [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: frameDelay,
                    kCGImagePropertyGIFUnclampedDelayTime: frameDelay
                ]
            ]
        case .apng:
            [
                kCGImagePropertyPNGDictionary: [
                    kCGImagePropertyAPNGDelayTime: frameDelay,
                    kCGImagePropertyAPNGUnclampedDelayTime: frameDelay
                ]
            ]
        case .av1, .hevc, .mp4, .webm:
            [:]
        }
    }

    private func render(
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
            throw ImageIOAnimatedMediaExporterError.cannotCreateFrameContext
        }

        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: outputSize))
        context.interpolationQuality = .high
        context.draw(image, in: drawRect(for: image, outputSize: outputSize, shouldCrop: shouldCrop))

        guard let renderedImage = context.makeImage() else {
            throw ImageIOAnimatedMediaExporterError.cannotRenderFrame
        }

        return renderedImage
    }

    private func renderBitmap(
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
                throw ImageIOAnimatedMediaExporterError.cannotCreateFrameContext
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

public enum ImageIOAnimatedMediaExporterError: Error, Equatable {
    case unsupportedFormat(ExportFormat)
    case cannotCreateDestination
    case cannotCreateFrameContext
    case cannotRenderFrame
    case finalizeFailed
}
