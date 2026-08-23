import Foundation

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
            sampleByteCounts.allSatisfy({ $0 > 0 })
        else {
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

struct SampledAnimatedSizeEstimateCacheKey: Hashable, Sendable {
    let inputFileURL: URL
    let format: ExportFormat
    let width: Int
    let height: Int
    let framesPerSecond: Int
    let trimStart: TimeInterval
    let trimEnd: TimeInterval
    let cuts: [SampledAnimatedCutCacheKey]
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

struct SampledAnimatedCutCacheKey: Hashable, Sendable {
    let start: TimeInterval
    let end: TimeInterval

    init(_ cut: TimelineCut) {
        start = cut.sourceRange.start
        end = cut.sourceRange.end
    }
}

struct SampledAnimatedZoomBlockCacheKey: Hashable, Sendable {
    let start: TimeInterval
    let end: TimeInterval
    let originX: Double
    let originY: Double
    let width: Double
    let height: Double
    let zoom: Double
    let transitionOverride: TimeInterval?

    init(_ block: ZoomBlock) {
        start = block.timeRange.start
        end = block.timeRange.end
        originX = block.targetRect.originX
        originY = block.targetRect.originY
        width = block.targetRect.width
        height = block.targetRect.height
        zoom = block.zoom
        transitionOverride = block.transitionOverride
    }
}

actor SampledAnimatedSizeEstimateCache {
    private var estimates: [SampledAnimatedSizeEstimateCacheKey: ExportEstimate] = [:]

    func estimate(for key: SampledAnimatedSizeEstimateCacheKey) -> ExportEstimate? {
        estimates[key]
    }

    func store(_ estimate: ExportEstimate, for key: SampledAnimatedSizeEstimateCacheKey) {
        estimates[key] = estimate
    }
}
