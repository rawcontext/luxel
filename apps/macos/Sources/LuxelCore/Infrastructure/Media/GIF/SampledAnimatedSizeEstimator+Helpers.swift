import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ImageIO
import UniformTypeIdentifiers

extension SampledAnimatedSizeEstimator {
    func renderedFrame(
        atFrameIndex index: Int,
        request: ExportRequest,
        outputPixelSize: PixelSize,
        schedule: AnimatedFrameSchedule,
        imageGenerator: AVAssetImageGenerator
    ) async throws -> CGImage {
        let sourceFrame = try await imageGenerator.image(
            at: schedule.frameTimes[index]
        ).image
        let cameraPath = try cameraPath(for: request, sourceFrame: sourceFrame)
        return try AnimatedFrameRenderer().renderImage(
            sourceFrame,
            outputPixelSize: outputPixelSize,
            shouldCrop: request.shouldCrop,
            sourceCropRect: request.cropRect,
            cameraTransform: try cameraTransform(
                for: schedule.frameTimes[index],
                request: request,
                cameraPath: cameraPath
            )
        )
    }

    func renderedGIFFrame(
        atFrameIndex index: Int,
        request: ExportRequest,
        outputPixelSize: PixelSize,
        schedule: AnimatedFrameSchedule,
        backgroundMatte: RGBColor? = nil,
        imageGenerator: AVAssetImageGenerator
    ) async throws -> GIFFrameBitmap {
        let sourceFrame = try await imageGenerator.image(
            at: schedule.frameTimes[index]
        ).image
        let cameraPath = try cameraPath(for: request, sourceFrame: sourceFrame)
        return try AnimatedFrameRenderer().renderGIFBitmap(
            sourceFrame,
            outputPixelSize: outputPixelSize,
            shouldCrop: request.shouldCrop,
            sourceCropRect: request.cropRect,
            backgroundMatte: backgroundMatte,
            cameraTransform: try cameraTransform(
                for: schedule.frameTimes[index],
                request: request,
                cameraPath: cameraPath
            )
        )
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
            speed: request.speed
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

        let outputTime = max(0, (sourceTime.seconds - request.timeRange.start) / request.speed.value)
        return try cameraPath.transform(at: outputTime)
    }

    func encodedByteCount(
        frames: [CGImage],
        format: ExportFormat,
        frameDelay: TimeInterval,
        loopMode: GIFLoopMode = .forever
    ) throws -> Int {
        let data = NSMutableData()
        let typeIdentifier = try typeIdentifier(for: format)
        guard
            let destination = CGImageDestinationCreateWithData(
                data as CFMutableData,
                typeIdentifier as CFString,
                frames.count,
                nil
            )
        else {
            throw SampledAnimatedSizeEstimatorError.cannotCreateDestination
        }

        CGImageDestinationSetProperties(
            destination,
            destinationProperties(for: format, loopMode: loopMode) as CFDictionary
        )

        for frame in frames {
            CGImageDestinationAddImage(
                destination,
                frame,
                frameProperties(for: format, frameDelay: frameDelay) as CFDictionary
            )
        }

        guard CGImageDestinationFinalize(destination) else {
            throw SampledAnimatedSizeEstimatorError.finalizeFailed
        }

        return data.length
    }

    func gifEncodedByteCount(
        frames: [GIFFrameBitmap],
        outputPixelSize: PixelSize,
        frameDelay: TimeInterval,
        options: GIFRenderOptions,
        encoder: NativeGIFEncoder
    ) throws -> Int {
        try encoder.data(
            pixelSize: outputPixelSize,
            frames: frames,
            frameDelay: frameDelay,
            options: options
        ).count
    }

    func outputFrameCount(baseFrameCount: Int, loopMode: GIFLoopMode) throws -> Int {
        try GIFFrameSequencePlanner()
            .frameIndexes(frameCount: baseFrameCount, loopMode: loopMode)
            .count
    }

    func sequencedFrames<T>(_ frames: [T], loopMode: GIFLoopMode) throws -> [T] {
        let frameIndexes = try GIFFrameSequencePlanner()
            .frameIndexes(frameCount: frames.count, loopMode: loopMode)
        return frameIndexes.map { frames[$0] }
    }

    func sampleFrameIndices(totalFrameCount: Int, requestedSampleCount: Int) -> [Int] {
        let sampleCount = min(max(1, requestedSampleCount), totalFrameCount)
        guard sampleCount > 1 else {
            return [0]
        }

        return (0..<sampleCount).map { index in
            Int((Double(index) * Double(totalFrameCount - 1) / Double(sampleCount - 1)).rounded())
        }
    }

    func adjacentPairStartIndices(totalFrameCount: Int) -> [Int] {
        guard totalFrameCount > 1 else {
            return []
        }

        let middleStart = max(0, min(totalFrameCount - 2, (totalFrameCount / 2) - 1))
        return Array(Set([0, middleStart])).sorted()
    }

    func typeIdentifier(for format: ExportFormat) throws -> String {
        switch format {
        case .gif:
            UTType.gif.identifier
        case .apng:
            UTType.png.identifier
        case .av1, .hevc, .proRes422, .proRes4444, .m4a, .alac, .wav, .caf, .flac, .mp4, .webm:
            throw SampledAnimatedSizeEstimatorError.unsupportedFormat(format)
        }
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

    func gifRenderOptions(for request: ExportRequest) throws -> GIFRenderOptions? {
        guard request.format == .gif else {
            return nil
        }

        if let gifOptions = request.gifOptions {
            return gifOptions
        }

        return try GIFRenderOptions(quality: request.resolvedQuality)
    }

    func animatedLoopMode(for request: ExportRequest) -> GIFLoopMode {
        switch request.format {
        case .gif:
            request.gifOptions?.loopMode ?? .forever
        case .apng:
            request.gifOptions?.loopMode ?? .forever
        case .av1, .hevc, .proRes422, .proRes4444, .m4a, .alac, .wav, .caf, .flac, .mp4, .webm:
            .forever
        }
    }
}
