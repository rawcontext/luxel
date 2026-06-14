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
        case .mp4, .hevc:
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
                imageGenerator: imageGenerator
            )
            let secondFrame = try await renderedGIFFrame(
                atFrameIndex: startIndex + 1,
                request: request,
                outputPixelSize: outputPixelSize,
                schedule: schedule,
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

    private func renderedFrame(
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
            cameraTransform: try cameraTransform(
                for: schedule.frameTimes[index],
                request: request,
                cameraPath: cameraPath
            )
        )
    }

    private func renderedGIFFrame(
        atFrameIndex index: Int,
        request: ExportRequest,
        outputPixelSize: PixelSize,
        schedule: AnimatedFrameSchedule,
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
            cameraTransform: try cameraTransform(
                for: schedule.frameTimes[index],
                request: request,
                cameraPath: cameraPath
            )
        )
    }

    private func cameraPath(
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

    private func cameraTransform(
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

    private func encodedByteCount(
        frames: [CGImage],
        format: ExportFormat,
        frameDelay: TimeInterval,
        loopMode: GIFLoopMode = .forever
    ) throws -> Int {
        let data = NSMutableData()
        let typeIdentifier = try typeIdentifier(for: format)
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData,
            typeIdentifier as CFString,
            frames.count,
            nil
        ) else {
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

    private func gifEncodedByteCount(
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

    private func outputFrameCount(baseFrameCount: Int, loopMode: GIFLoopMode) throws -> Int {
        try GIFFrameSequencePlanner()
            .frameIndexes(frameCount: baseFrameCount, loopMode: loopMode)
            .count
    }

    private func sequencedFrames<T>(_ frames: [T], loopMode: GIFLoopMode) throws -> [T] {
        let frameIndexes = try GIFFrameSequencePlanner()
            .frameIndexes(frameCount: frames.count, loopMode: loopMode)
        return frameIndexes.map { frames[$0] }
    }

    private func sampleFrameIndices(totalFrameCount: Int, requestedSampleCount: Int) -> [Int] {
        let sampleCount = min(max(1, requestedSampleCount), totalFrameCount)
        guard sampleCount > 1 else {
            return [0]
        }

        return (0..<sampleCount).map { index in
            Int((Double(index) * Double(totalFrameCount - 1) / Double(sampleCount - 1)).rounded())
        }
    }

    private func adjacentPairStartIndices(totalFrameCount: Int) -> [Int] {
        guard totalFrameCount > 1 else {
            return []
        }

        let middleStart = max(0, min(totalFrameCount - 2, (totalFrameCount / 2) - 1))
        return Array(Set([0, middleStart])).sorted()
    }

    private func typeIdentifier(for format: ExportFormat) throws -> String {
        switch format {
        case .gif:
            UTType.gif.identifier
        case .apng:
            UTType.png.identifier
        case .av1, .hevc, .mp4, .webm:
            throw SampledAnimatedSizeEstimatorError.unsupportedFormat(format)
        }
    }

    private func destinationProperties(
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
        case .av1, .hevc, .mp4, .webm:
            [:]
        }
    }

    private func destinationPNGProperties(loopMode: GIFLoopMode) -> [CFString: Any] {
        guard let loopCount = loopMode.imageIOLoopCount else {
            return [:]
        }

        return [
            kCGImagePropertyPNGDictionary: [
                kCGImagePropertyAPNGLoopCount: loopCount
            ]
        ]
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

    private func gifRenderOptions(for request: ExportRequest) throws -> GIFRenderOptions? {
        guard request.format == .gif else {
            return nil
        }

        if let gifOptions = request.gifOptions {
            return gifOptions
        }

        return try GIFRenderOptions(quality: request.resolvedQuality)
    }

    private func animatedLoopMode(for request: ExportRequest) -> GIFLoopMode {
        switch request.format {
        case .gif:
            request.gifOptions?.loopMode ?? .forever
        case .apng:
            request.gifOptions?.loopMode ?? .forever
        case .av1, .hevc, .mp4, .webm:
            .forever
        }
    }
}

public enum SampledAnimatedSizeEstimatorError: Error, Equatable {
    case unsupportedFormat(ExportFormat)
    case cannotCreateDestination
    case cannotCreateFrameContext
    case cannotRenderFrame
    case finalizeFailed
    case invalidSampleData
}

struct SampledAnimatedAdjacentPairSize: Equatable, Sendable {
    let firstBytes: Int
    let secondBytes: Int
    let combinedBytes: Int

    var compressionRatio: Double? {
        let singleFrameBytes = firstBytes + secondBytes
        guard singleFrameBytes > 0, combinedBytes > 0 else {
            return nil
        }

        return Double(combinedBytes) / Double(singleFrameBytes)
    }
}

struct SampledAnimatedEstimateModel: Equatable, Sendable {
    let totalFrameCount: Int
    let sampleByteCounts: [Int]
    let adjacentPairs: [SampledAnimatedAdjacentPairSize]

    init(
        totalFrameCount: Int,
        sampleByteCounts: [Int],
        adjacentPairs: [SampledAnimatedAdjacentPairSize]
    ) throws {
        guard totalFrameCount > 0, !sampleByteCounts.isEmpty,
              sampleByteCounts.allSatisfy({ $0 > 0 }) else {
            throw SampledAnimatedSizeEstimatorError.invalidSampleData
        }

        self.totalFrameCount = totalFrameCount
        self.sampleByteCounts = sampleByteCounts
        self.adjacentPairs = adjacentPairs
    }

    var estimatedByteCount: Int64 {
        let averageFrameBytes = Double(sampleByteCounts.reduce(0, +)) / Double(sampleByteCounts.count)
        let correctedFrameBytes = averageFrameBytes * compressionCorrectionFactor
        return Int64((correctedFrameBytes * Double(totalFrameCount)).rounded(.up))
    }

    private var compressionCorrectionFactor: Double {
        let ratios = adjacentPairs.compactMap(\.compressionRatio)
        guard !ratios.isEmpty else {
            return 1
        }

        let averageRatio = ratios.reduce(0, +) / Double(ratios.count)
        return min(1, max(0.35, averageRatio))
    }
}

private struct SampledAnimatedSizeEstimateCacheKey: Hashable, Sendable {
    let inputFileURL: URL
    let format: ExportFormat
    let width: Int
    let height: Int
    let framesPerSecond: Int
    let trimStart: TimeInterval
    let trimEnd: TimeInterval
    let speed: Double
    let shouldCrop: Bool
    let quality: ExportQuality
    let gifLoopMode: GIFLoopMode?
    let gifDithering: GIFDitheringMode?
    let gifPaletteSize: Int?
    let gifLossyTolerance: Int?
    let gifBackgroundMatte: RGBColor?
    let zoomBlocks: [SampledAnimatedZoomBlockCacheKey]
}

private struct SampledAnimatedZoomBlockCacheKey: Hashable, Sendable {
    let start: TimeInterval
    let end: TimeInterval
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let zoom: Double
    let transitionOverride: TimeInterval?

    init(_ block: ZoomBlock) {
        start = block.timeRange.start
        end = block.timeRange.end
        x = block.targetRect.x
        y = block.targetRect.y
        width = block.targetRect.width
        height = block.targetRect.height
        zoom = block.zoom
        transitionOverride = block.transitionOverride
    }
}

private actor SampledAnimatedSizeEstimateCache {
    private var estimates: [SampledAnimatedSizeEstimateCacheKey: ExportEstimate] = [:]

    func estimate(for key: SampledAnimatedSizeEstimateCacheKey) -> ExportEstimate? {
        estimates[key]
    }

    func store(_ estimate: ExportEstimate, for key: SampledAnimatedSizeEstimateCacheKey) {
        estimates[key] = estimate
    }
}
