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

extension ImageIOAnimatedMediaExporter {
    fileprivate func exportAPNG(
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
            try await forEachRenderedFrame(
                context: context,
                frameTimes: frameTimes,
                progressScale: 0.95,
                progress: progress
            ) { renderedFrame in
                CGImageDestinationAddImage(
                    destination,
                    renderedFrame,
                    AnimatedImageIOProperties.frame(
                        format: request.format,
                        delay: context.schedule.frameDelay
                    ) as CFDictionary
                )
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

    fileprivate func makeAPNGDestination(
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
        let properties = AnimatedImageIOProperties.destination(
            format: context.request.format,
            loopMode: loopMode
        )
        CGImageDestinationSetProperties(destination, properties as CFDictionary)
        return (destination, frameTimes)
    }

    fileprivate func exportGIF(
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

    fileprivate func renderedBitmaps(
        context: ImageIOAnimatedExportContext,
        backgroundMatte: RGBColor?,
        progress: MediaExportProgressHandler?
    ) async throws -> [GIFFrameBitmap] {
        var frames: [GIFFrameBitmap] = []
        frames.reserveCapacity(context.schedule.frameTimes.count)
        try await forEachRenderedFrame(
            context: context,
            frameTimes: context.schedule.frameTimes,
            progress: progress
        ) { compositedFrame in
            frames.append(
                try AnimatedFrameRenderer().renderGIFBitmap(
                    compositedFrame,
                    outputPixelSize: context.outputPixelSize,
                    shouldCrop: false,
                    backgroundMatte: backgroundMatte
                )
            )
        }

        return frames
    }

    fileprivate func forEachRenderedFrame(
        context: ImageIOAnimatedExportContext,
        frameTimes: [CMTime],
        progressScale: Double = 1,
        progress: MediaExportProgressHandler?,
        body: (CGImage) throws -> Void
    ) async throws {
        let request = context.request
        var cameraPath: CameraPath?
        var didBuildCameraPath = false
        let keystrokeTimeline = try? KeystrokeSidecarFileLoader().load(
            nextTo: request.inputFileURL
        )
        let keystrokeCompositor = await KeystrokeFrameCompositor()

        await progress?(0)
        for (frameIndex, time) in frameTimes.enumerated() {
            let frame = try await context.imageGenerator.image(at: time).image
            if !didBuildCameraPath {
                cameraPath = try request.animatedCameraPath(sourceFrame: frame)
                didBuildCameraPath = true
            }
            let baseFrame = try AnimatedFrameRenderer().renderImage(
                frame,
                outputPixelSize: context.outputPixelSize,
                shouldCrop: request.shouldCrop,
                sourceCropRect: request.cropRect,
                cameraTransform: try request.animatedCameraTransform(
                    at: time,
                    cameraPath: cameraPath
                )
            )
            try body(
                await keystrokeCompositor.composite(
                    baseFrame,
                    timeline: keystrokeTimeline,
                    options: request.keystrokeOptions,
                    at: time.seconds
                )
            )
            await progress?(
                Double(frameIndex + 1) / Double(max(1, frameTimes.count)) * progressScale
            )
        }
    }

    fileprivate func animatedLoopMode(for request: ExportRequest) -> GIFLoopMode {
        request.gifOptions?.loopMode ?? .forever
    }

    fileprivate func sequencedFrameTimes(
        _ frameTimes: [CMTime],
        loopMode: GIFLoopMode
    ) throws -> [CMTime] {
        let frameIndexes = try GIFFrameSequencePlanner()
            .frameIndexes(frameCount: frameTimes.count, loopMode: loopMode)
        return frameIndexes.map { frameTimes[$0] }
    }

    fileprivate func makeDestination(
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
