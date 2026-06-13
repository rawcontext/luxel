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
        let totalFrameCount = frameCount(for: request)
        let key = SampledAnimatedSizeEstimateCacheKey(
            inputFileURL: request.inputFileURL.standardizedFileURL,
            format: request.format,
            width: outputPixelSize.width,
            height: outputPixelSize.height,
            framesPerSecond: request.frameRate.framesPerSecond,
            trimStart: request.timeRange.start,
            trimEnd: request.timeRange.end,
            shouldCrop: request.shouldCrop,
            quality: request.resolvedQuality
        )

        if let cached = await cache.estimate(for: key) {
            return cached
        }

        let estimate = try await estimateUncached(
            request,
            outputPixelSize: outputPixelSize,
            totalFrameCount: totalFrameCount
        )
        await cache.store(estimate, for: key)
        return estimate
    }

    private func estimateUncached(
        _ request: ExportRequest,
        outputPixelSize: PixelSize,
        totalFrameCount: Int
    ) async throws -> ExportEstimate {
        let asset = AVURLAsset(url: request.inputFileURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceBefore = .zero
        imageGenerator.requestedTimeToleranceAfter = .zero

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
                imageGenerator: imageGenerator
            )
            sampleFrames.append(frame)
            sampleByteCounts.append(try encodedByteCount(
                frames: [frame],
                format: request.format,
                frameDelay: frameDelay(for: request)
            ))
        }

        if sampleFrames.count == totalFrameCount {
            let bytes = try encodedByteCount(
                frames: sampleFrames,
                format: request.format,
                frameDelay: frameDelay(for: request)
            )
            return try ExportEstimate(bytes: Int64(bytes), confidence: .sampled)
        }

        let adjacentPairs = try await adjacentPairSizes(
            request: request,
            outputPixelSize: outputPixelSize,
            totalFrameCount: totalFrameCount,
            imageGenerator: imageGenerator
        )
        let model = try SampledAnimatedEstimateModel(
            totalFrameCount: totalFrameCount,
            sampleByteCounts: sampleByteCounts,
            adjacentPairs: adjacentPairs
        )

        return try ExportEstimate(bytes: model.estimatedByteCount, confidence: .sampled)
    }

    private func adjacentPairSizes(
        request: ExportRequest,
        outputPixelSize: PixelSize,
        totalFrameCount: Int,
        imageGenerator: AVAssetImageGenerator
    ) async throws -> [SampledAnimatedAdjacentPairSize] {
        let pairStartIndices = adjacentPairStartIndices(totalFrameCount: totalFrameCount)
        var pairs: [SampledAnimatedAdjacentPairSize] = []

        for startIndex in pairStartIndices {
            try Task.checkCancellation()
            let firstFrame = try await renderedFrame(
                atFrameIndex: startIndex,
                request: request,
                outputPixelSize: outputPixelSize,
                imageGenerator: imageGenerator
            )
            let secondFrame = try await renderedFrame(
                atFrameIndex: startIndex + 1,
                request: request,
                outputPixelSize: outputPixelSize,
                imageGenerator: imageGenerator
            )
            let frameDelay = frameDelay(for: request)
            let firstBytes = try encodedByteCount(
                frames: [firstFrame],
                format: request.format,
                frameDelay: frameDelay
            )
            let secondBytes = try encodedByteCount(
                frames: [secondFrame],
                format: request.format,
                frameDelay: frameDelay
            )
            let combinedBytes = try encodedByteCount(
                frames: [firstFrame, secondFrame],
                format: request.format,
                frameDelay: frameDelay
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
        imageGenerator: AVAssetImageGenerator
    ) async throws -> CGImage {
        let sourceFrame = try await imageGenerator.image(
            at: frameTime(atFrameIndex: index, for: request)
        ).image
        return try render(
            sourceFrame,
            outputPixelSize: outputPixelSize,
            shouldCrop: request.shouldCrop
        )
    }

    private func encodedByteCount(
        frames: [CGImage],
        format: ExportFormat,
        frameDelay: TimeInterval
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
            destinationProperties(for: format) as CFDictionary
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

    private func frameCount(for request: ExportRequest) -> Int {
        max(1, Int((request.timeRange.duration * Double(request.frameRate.framesPerSecond)).rounded()))
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

    private func frameTime(atFrameIndex index: Int, for request: ExportRequest) -> CMTime {
        CMTime(
            seconds: request.timeRange.start + (Double(index) / Double(request.frameRate.framesPerSecond)),
            preferredTimescale: 600
        )
    }

    private func frameDelay(for request: ExportRequest) -> TimeInterval {
        1 / Double(request.frameRate.framesPerSecond)
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
            throw SampledAnimatedSizeEstimatorError.cannotCreateFrameContext
        }

        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: outputSize))
        context.interpolationQuality = .high
        context.draw(image, in: drawRect(for: image, outputSize: outputSize, shouldCrop: shouldCrop))

        guard let renderedImage = context.makeImage() else {
            throw SampledAnimatedSizeEstimatorError.cannotRenderFrame
        }

        return renderedImage
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
    let shouldCrop: Bool
    let quality: ExportQuality
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
