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
                let renderedFrame = try AnimatedFrameRenderer().renderImage(
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

        let encoder = NativeGIFEncoder()
        let baseFrames = try await renderedBitmaps(
            for: schedule,
            outputPixelSize: outputPixelSize,
            shouldCrop: request.shouldCrop,
            imageGenerator: imageGenerator
        )
        let frames = try encoder.sequencedFrames(from: baseFrames, loopMode: options.loopMode)
        let data = try encoder.data(
            pixelSize: outputPixelSize,
            frames: frames,
            frameDelay: schedule.frameDelay,
            options: options
        )

        try? FileManager.default.removeItem(at: outputFileURL)
        do {
            try data.write(to: outputFileURL, options: .atomic)
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
            frames.append(try AnimatedFrameRenderer().renderGIFBitmap(
                frame,
                outputPixelSize: outputPixelSize,
                shouldCrop: shouldCrop
            ))
        }

        return frames
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

}

public enum ImageIOAnimatedMediaExporterError: Error, Equatable {
    case unsupportedFormat(ExportFormat)
    case cannotCreateDestination
    case cannotCreateFrameContext
    case cannotRenderFrame
    case finalizeFailed
}
