import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ImageIOAnimatedMediaExporter: MediaExporter, Sendable {
    public init() {}

    public func export(
        _ input: MediaExportInput,
        to outputFileURL: URL,
        progress: MediaExportProgressHandler?
    ) async throws -> ExportedMedia {
        let request = input.request
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
        let context = ImageIOAnimatedExportContext(
            request: request,
            outputPixelSize: outputPixelSize,
            schedule: schedule,
            imageGenerator: imageGenerator
        )

        if request.format == .gif {
            try await exportGIF(
                context,
                to: outputFileURL,
                progress: progress
            )
        } else {
            try await exportAPNG(context, to: outputFileURL, progress: progress)
        }

        return ExportedMedia(
            fileURL: outputFileURL,
            format: request.format,
            pixelSize: outputPixelSize,
            shouldMute: request.outputShouldMute
        )
    }
}

private extension ImageIOAnimatedMediaExporter {
    func exportAPNG(
        _ context: ImageIOAnimatedExportContext,
        to outputFileURL: URL,
        progress: MediaExportProgressHandler?
    ) async throws {
        let request = context.request
        let (destination, frameTimes) = try makeAPNGDestination(
            context: context,
            outputFileURL: outputFileURL
        )

        try? FileManager.default.removeItem(at: outputFileURL)

        do {
            var cameraPath: CameraPath?
            var didBuildCameraPath = false

            await progress?(0)
            for (frameIndex, time) in frameTimes.enumerated() {
                let frame = try await context.imageGenerator.image(at: time).image
                if !didBuildCameraPath {
                    cameraPath = try self.cameraPath(for: request, sourceFrame: frame)
                    didBuildCameraPath = true
                }

                let renderedFrame = try AnimatedFrameRenderer().renderImage(
                    frame,
                    outputPixelSize: context.outputPixelSize,
                    shouldCrop: request.shouldCrop,
                    sourceCropRect: request.cropRect,
                    cameraTransform: try cameraTransform(
                        for: time,
                        request: request,
                        cameraPath: cameraPath
                    )
                )
                CGImageDestinationAddImage(
                    destination,
                    renderedFrame,
                    frameProperties(
                        for: request.format,
                        frameDelay: context.schedule.frameDelay
                    ) as CFDictionary
                )
                await progress?(Double(frameIndex + 1) / Double(max(1, frameTimes.count)) * 0.95)
            }

            guard CGImageDestinationFinalize(destination) else {
                throw ImageIOAnimatedMediaExporterError.finalizeFailed
            }
            await progress?(1)
        } catch {
            try? FileManager.default.removeItem(at: outputFileURL)
            throw error
        }
    }

    func makeAPNGDestination(
        context: ImageIOAnimatedExportContext,
        outputFileURL: URL
    ) throws -> (CGImageDestination, [CMTime]) {
        let loopMode = animatedLoopMode(for: context.request)
        let frameTimes = try sequencedFrameTimes(
            context.schedule.frameTimes,
            loopMode: loopMode
        )
        let destination = try makeDestination(
            format: context.request.format,
            outputFileURL: outputFileURL,
            frameCount: frameTimes.count
        )
        let properties = destinationProperties(
            for: context.request.format,
            loopMode: loopMode
        )
        CGImageDestinationSetProperties(destination, properties as CFDictionary)
        return (destination, frameTimes)
    }

    func exportGIF(
        _ context: ImageIOAnimatedExportContext,
        to outputFileURL: URL,
        progress: MediaExportProgressHandler?
    ) async throws {
        let request = context.request
        let options: GIFRenderOptions
        if let gifOptions = request.gifOptions {
            options = gifOptions
        } else {
            options = try GIFRenderOptions(quality: request.resolvedQuality)
        }

        let encoder = NativeGIFEncoder()
        let baseFrames = try await renderedBitmaps(
            context: context,
            backgroundMatte: options.backgroundMatte,
            progress: { value in
                await progress?(value * 0.9)
            }
        )
        await progress?(0.92)
        let frames = try encoder.sequencedFrames(from: baseFrames, loopMode: options.loopMode)
        await progress?(0.95)
        let data = try encoder.data(
            pixelSize: context.outputPixelSize,
            frames: frames,
            frameDelay: context.schedule.frameDelay,
            options: options
        )
        await progress?(0.98)

        try? FileManager.default.removeItem(at: outputFileURL)
        do {
            try data.write(to: outputFileURL, options: .atomic)
            await progress?(1)
        } catch {
            try? FileManager.default.removeItem(at: outputFileURL)
            throw error
        }
    }

    func renderedBitmaps(
        context: ImageIOAnimatedExportContext,
        backgroundMatte: RGBColor?,
        progress: MediaExportProgressHandler?
    ) async throws -> [GIFFrameBitmap] {
        let request = context.request
        var frames: [GIFFrameBitmap] = []
        frames.reserveCapacity(context.schedule.frameTimes.count)
        var cameraPath: CameraPath?
        var didBuildCameraPath = false

        await progress?(0)
        for (frameIndex, time) in context.schedule.frameTimes.enumerated() {
            let frame = try await context.imageGenerator.image(at: time).image
            if !didBuildCameraPath {
                cameraPath = try self.cameraPath(for: request, sourceFrame: frame)
                didBuildCameraPath = true
            }

            frames.append(
                try AnimatedFrameRenderer().renderGIFBitmap(
                    frame,
                    outputPixelSize: context.outputPixelSize,
                    shouldCrop: request.shouldCrop,
                    sourceCropRect: request.cropRect,
                    backgroundMatte: backgroundMatte,
                    cameraTransform: try cameraTransform(
                        for: time,
                        request: request,
                        cameraPath: cameraPath
                    )
                ))
            await progress?(
                Double(frameIndex + 1) / Double(max(1, context.schedule.frameTimes.count))
            )
        }

        return frames
    }

    func cameraPath(
        for request: ExportRequest,
        sourceFrame: CGImage
    ) throws -> CameraPath? {
        guard !request.zoomBlocks.isEmpty else {
            return nil
        }

        let blocks = try ZoomExportTimeMapper(
            trimRange: request.timeRange,
            speed: request.speed,
            editPlan: request.editPlan
        )
        .map(request.zoomBlocks)

        guard !blocks.isEmpty else {
            return nil
        }

        return try CameraPath(
            blocks: blocks,
            sourceSize: PixelSize(width: sourceFrame.width, height: sourceFrame.height)
        )
    }

    func cameraTransform(
        for sourceTime: CMTime,
        request: ExportRequest,
        cameraPath: CameraPath?
    ) throws -> CameraTransform {
        guard let cameraPath else {
            return .identity
        }

        guard let outputTime = request.timelineMapper.outputTime(
            forSourceTime: sourceTime.seconds
        ) else {
            return .identity
        }
        return try cameraPath.transform(at: outputTime)
    }

    func animatedLoopMode(for request: ExportRequest) -> GIFLoopMode {
        request.gifOptions?.loopMode ?? .forever
    }

    func sequencedFrameTimes(
        _ frameTimes: [CMTime],
        loopMode: GIFLoopMode
    ) throws -> [CMTime] {
        let frameIndexes = try GIFFrameSequencePlanner()
            .frameIndexes(frameCount: frameTimes.count, loopMode: loopMode)
        return frameIndexes.map { frameTimes[$0] }
    }

    func makeDestination(
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
        case .av1, .hevc, .proRes422, .proRes4444, .m4a, .alac, .wav, .caf, .flac, .mp4, .webm:
            throw ImageIOAnimatedMediaExporterError.unsupportedFormat(format)
        }

        guard
            let destination = CGImageDestinationCreateWithURL(
                outputFileURL as CFURL,
                typeIdentifier as CFString,
                frameCount,
                nil
            )
        else {
            throw ImageIOAnimatedMediaExporterError.cannotCreateDestination
        }

        return destination
    }

    func destinationProperties(
        for format: ExportFormat,
        loopMode: GIFLoopMode = .forever
    ) -> [CFString: Any] {
        switch format {
        case .gif:
            [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFLoopCount: loopMode.imageIOLoopCount ?? 0
                ]
            ]
        case .apng:
            destinationPNGProperties(loopMode: loopMode)
        case .av1, .hevc, .proRes422, .proRes4444, .m4a, .alac, .wav, .caf, .flac, .mp4, .webm:
            [:]
        }
    }

    func destinationPNGProperties(loopMode: GIFLoopMode) -> [CFString: Any] {
        guard let loopCount = loopMode.imageIOLoopCount else {
            return [:]
        }

        return [
            kCGImagePropertyPNGDictionary: [
                kCGImagePropertyAPNGLoopCount: loopCount
            ]
        ]
    }

    func frameProperties(
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
        case .av1, .hevc, .proRes422, .proRes4444, .m4a, .alac, .wav, .caf, .flac, .mp4, .webm:
            [:]
        }
    }

}

private struct ImageIOAnimatedExportContext {
    let request: ExportRequest
    let outputPixelSize: PixelSize
    let schedule: AnimatedFrameSchedule
    let imageGenerator: AVAssetImageGenerator
}

public enum ImageIOAnimatedMediaExporterError: Error, Equatable {
    case unsupportedFormat(ExportFormat)
    case cannotCreateDestination
    case cannotCreateFrameContext
    case cannotRenderFrame
    case finalizeFailed
}
