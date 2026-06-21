import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct NativeExportSizeEstimator: ExportSizeEstimator, Sendable {
    private let movieEstimator: BitrateModelSizeEstimator
    private let animatedEstimator: SampledAnimatedSizeEstimator

    public init(
        movieEstimator: BitrateModelSizeEstimator = BitrateModelSizeEstimator(),
        animatedEstimator: SampledAnimatedSizeEstimator = SampledAnimatedSizeEstimator()
    ) {
        self.movieEstimator = movieEstimator
        self.animatedEstimator = animatedEstimator
    }

    public func estimate(_ request: ExportRequest) async throws -> ExportEstimate {
        switch request.format {
        case .mp4, .hevc, .m4a, .alac, .wav, .caf, .flac:
            try await movieEstimator.estimate(request)
        case .gif, .apng:
            try await animatedEstimator.estimate(request)
        case .webm, .av1:
            throw NativeExportSizeEstimatorError.unsupportedFormat(request.format)
        }
    }
}

public enum NativeExportSizeEstimatorError: Error, Equatable {
    case unsupportedFormat(ExportFormat)
}

public struct SampledAnimatedSizeEstimator: ExportSizeEstimator, Sendable {
    private let sampleFrameCount: Int
    private let cache: SampledAnimatedSizeEstimateCache

    public init(sampleFrameCount: Int = 6) {
        self.sampleFrameCount = max(1, sampleFrameCount)
        cache = SampledAnimatedSizeEstimateCache()
    }
}

extension SampledAnimatedSizeEstimator {
    public func estimate(_ request: ExportRequest) async throws -> ExportEstimate {
        guard request.format == .gif || request.format == .apng else {
            throw SampledAnimatedSizeEstimatorError.unsupportedFormat(request.format)
        }

        let outputPixelSize = try request.outputPixelSize
        let asset = AVURLAsset(url: request.inputFileURL)
        let schedule = await animatedFrameSchedule(for: request, asset: asset)
        let totalFrameCount = schedule.frameTimes.count
        let gifOptions = try gifRenderOptions(for: request)
        let loopMode = animatedLoopMode(for: request)
        let key = SampledAnimatedSizeEstimateCacheKey(
            inputFileURL: request.inputFileURL.standardizedFileURL,
            format: request.format,
            width: outputPixelSize.width,
            height: outputPixelSize.height,
            framesPerSecond: request.frameRate.framesPerSecond,
            trimStart: request.timeRange.start,
            trimEnd: request.timeRange.end,
            speed: request.speed.value,
            shouldCrop: request.shouldCrop,
            quality: request.resolvedQuality,
            gifLoopMode: loopMode,
            gifDithering: gifOptions?.dithering,
            gifPaletteSize: gifOptions?.paletteSize,
            gifLossyTolerance: gifOptions?.lossyTolerance,
            gifBackgroundMatte: gifOptions?.backgroundMatte,
            zoomBlocks: request.zoomBlocks.map(SampledAnimatedZoomBlockCacheKey.init)
        )

        if let cached = await cache.estimate(for: key) {
            return cached
        }

        let estimate = try await estimateUncached(
            request,
            outputPixelSize: outputPixelSize,
            totalFrameCount: totalFrameCount,
            schedule: schedule,
            asset: asset
        )
        await cache.store(estimate, for: key)
        return estimate
    }

    private func estimateUncached(
        _ request: ExportRequest,
        outputPixelSize: PixelSize,
        totalFrameCount: Int,
        schedule: AnimatedFrameSchedule,
        asset: AVURLAsset
    ) async throws -> ExportEstimate {
        if request.format == .gif {
            return try await estimateGIFUncached(
                request,
                outputPixelSize: outputPixelSize,
                totalFrameCount: totalFrameCount,
                schedule: schedule,
                asset: asset
            )
        }

        return try await estimateImageIOUncached(
            request,
            outputPixelSize: outputPixelSize,
            totalFrameCount: totalFrameCount,
            schedule: schedule,
            asset: asset
        )
    }

    private func estimateImageIOUncached(
        _ request: ExportRequest,
        outputPixelSize: PixelSize,
        totalFrameCount: Int,
        schedule: AnimatedFrameSchedule,
        asset: AVURLAsset
    ) async throws -> ExportEstimate {
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero
        let loopMode = animatedLoopMode(for: request)

        let sampleIndices = sampleFrameIndices(
            totalFrameCount: totalFrameCount,
            requestedSampleCount: sampleFrameCount
        )
        var sampleFrames: [CGImage] = []
        var sampleByteCounts: [Int] = []

        for index in sampleIndices {
            try Task.checkCancellation()
            let frame = try await renderedFrame(
                atFrameIndex: index,
                request: request,
                outputPixelSize: outputPixelSize,
                schedule: schedule,
                imageGenerator: imageGenerator
            )
            sampleFrames.append(frame)
            sampleByteCounts.append(try encodedByteCount(
                frames: [frame],
                format: request.format,
                frameDelay: schedule.frameDelay,
                loopMode: loopMode
            ))
        }

        if sampleFrames.count == totalFrameCount {
            let frames = try sequencedFrames(sampleFrames, loopMode: loopMode)
            let bytes = try encodedByteCount(
                frames: frames,
                format: request.format,
                frameDelay: schedule.frameDelay,
                loopMode: loopMode
            )
            return try ExportEstimate(bytes: Int64(bytes), confidence: .sampled)
        }

        let adjacentPairs = try await adjacentPairSizes(
            request: request,
            outputPixelSize: outputPixelSize,
            totalFrameCount: totalFrameCount,
            schedule: schedule,
            imageGenerator: imageGenerator
        )
        let model = try SampledAnimatedEstimateModel(
            totalFrameCount: try outputFrameCount(
                baseFrameCount: totalFrameCount,
                loopMode: loopMode
            ),
            sampleByteCounts: sampleByteCounts,
            adjacentPairs: adjacentPairs
        )

        return try ExportEstimate(bytes: model.estimatedByteCount, confidence: .sampled)
    }

    private func estimateGIFUncached(
        _ request: ExportRequest,
        outputPixelSize: PixelSize,
        totalFrameCount: Int,
        schedule: AnimatedFrameSchedule,
        asset: AVURLAsset
    ) async throws -> ExportEstimate {
        guard let options = try gifRenderOptions(for: request) else {
            throw SampledAnimatedSizeEstimatorError.unsupportedFormat(request.format)
        }

        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero

        let sampleIndices = sampleFrameIndices(
            totalFrameCount: totalFrameCount,
            requestedSampleCount: sampleFrameCount
        )
        let encoder = NativeGIFEncoder()
        var sampleFrames: [GIFFrameBitmap] = []
        var sampleByteCounts: [Int] = []

        for index in sampleIndices {
            try Task.checkCancellation()
            let frame = try await renderedGIFFrame(
                atFrameIndex: index,
                request: request,
                outputPixelSize: outputPixelSize,
                schedule: schedule,
                backgroundMatte: options.backgroundMatte,
                imageGenerator: imageGenerator
            )
            sampleFrames.append(frame)
            sampleByteCounts.append(try gifEncodedByteCount(
                frames: [frame],
                outputPixelSize: outputPixelSize,
                frameDelay: schedule.frameDelay,
                options: options,
                encoder: encoder
            ))
        }

        if sampleFrames.count == totalFrameCount {
            let frames = try encoder.sequencedFrames(from: sampleFrames, loopMode: options.loopMode)
            let bytes = try gifEncodedByteCount(
                frames: frames,
                outputPixelSize: outputPixelSize,
                frameDelay: schedule.frameDelay,
                options: options,
                encoder: encoder
            )
            return try ExportEstimate(bytes: Int64(bytes), confidence: .sampled)
        }

        let adjacentPairs = try await gifAdjacentPairSizes(
            request: request,
            outputPixelSize: outputPixelSize,
            totalFrameCount: totalFrameCount,
            schedule: schedule,
            imageGenerator: imageGenerator,
            options: options,
            encoder: encoder
        )
        let model = try SampledAnimatedEstimateModel(
            totalFrameCount: try outputFrameCount(baseFrameCount: totalFrameCount, loopMode: options.loopMode),
            sampleByteCounts: sampleByteCounts,
            adjacentPairs: adjacentPairs
        )

        return try ExportEstimate(bytes: model.estimatedByteCount, confidence: .sampled)
    }

    private func adjacentPairSizes(
        request: ExportRequest,
        outputPixelSize: PixelSize,
        totalFrameCount: Int,
        schedule: AnimatedFrameSchedule,
        imageGenerator: AVAssetImageGenerator
    ) async throws -> [SampledAnimatedAdjacentPairSize] {
        let pairStartIndices = adjacentPairStartIndices(totalFrameCount: totalFrameCount)
        var pairs: [SampledAnimatedAdjacentPairSize] = []
        let loopMode = animatedLoopMode(for: request)

        for startIndex in pairStartIndices {
            try Task.checkCancellation()
            let firstFrame = try await renderedFrame(
                atFrameIndex: startIndex,
                request: request,
                outputPixelSize: outputPixelSize,
                schedule: schedule,
                imageGenerator: imageGenerator
            )
            let secondFrame = try await renderedFrame(
                atFrameIndex: startIndex + 1,
                request: request,
                outputPixelSize: outputPixelSize,
                schedule: schedule,
                imageGenerator: imageGenerator
            )
            let frameDelay = schedule.frameDelay
            let firstBytes = try encodedByteCount(
                frames: [firstFrame],
                format: request.format,
                frameDelay: frameDelay,
                loopMode: loopMode
            )
            let secondBytes = try encodedByteCount(
                frames: [secondFrame],
                format: request.format,
                frameDelay: frameDelay,
                loopMode: loopMode
            )
            let combinedBytes = try encodedByteCount(
                frames: [firstFrame, secondFrame],
                format: request.format,
                frameDelay: frameDelay,
                loopMode: loopMode
            )
            pairs.append(SampledAnimatedAdjacentPairSize(
                firstBytes: firstBytes,
                secondBytes: secondBytes,
                combinedBytes: combinedBytes
            ))
        }

        return pairs
    }

    private func gifAdjacentPairSizes(
        request: ExportRequest,
        outputPixelSize: PixelSize,
        totalFrameCount: Int,
        schedule: AnimatedFrameSchedule,
        imageGenerator: AVAssetImageGenerator,
        options: GIFRenderOptions,
        encoder: NativeGIFEncoder
    ) async throws -> [SampledAnimatedAdjacentPairSize] {
        let pairStartIndices = adjacentPairStartIndices(totalFrameCount: totalFrameCount)
        var pairs: [SampledAnimatedAdjacentPairSize] = []

        for startIndex in pairStartIndices {
            try Task.checkCancellation()
            let firstFrame = try await renderedGIFFrame(
                atFrameIndex: startIndex,
                request: request,
                outputPixelSize: outputPixelSize,
                schedule: schedule,
                backgroundMatte: options.backgroundMatte,
                imageGenerator: imageGenerator
            )
            let secondFrame = try await renderedGIFFrame(
                atFrameIndex: startIndex + 1,
                request: request,
                outputPixelSize: outputPixelSize,
                schedule: schedule,
                backgroundMatte: options.backgroundMatte,
                imageGenerator: imageGenerator
            )
            let frameDelay = schedule.frameDelay
            let firstBytes = try gifEncodedByteCount(
                frames: [firstFrame],
                outputPixelSize: outputPixelSize,
                frameDelay: frameDelay,
                options: options,
                encoder: encoder
            )
            let secondBytes = try gifEncodedByteCount(
                frames: [secondFrame],
                outputPixelSize: outputPixelSize,
                frameDelay: frameDelay,
                options: options,
                encoder: encoder
            )
            let combinedBytes = try gifEncodedByteCount(
                frames: [firstFrame, secondFrame],
                outputPixelSize: outputPixelSize,
                frameDelay: frameDelay,
                options: options,
                encoder: encoder
            )
            pairs.append(SampledAnimatedAdjacentPairSize(
                firstBytes: firstBytes,
                secondBytes: secondBytes,
                combinedBytes: combinedBytes
            ))
        }

        return pairs
    }

}
