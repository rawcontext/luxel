import AVFoundation
import CoreMedia
import Foundation

public struct AVFoundationExportPlan {
    public let inputFileURL: URL
    public let outputFileURL: URL
    public let presetName: String
    public let outputFileType: AVFileType?
    public let timeRange: CMTimeRange
    public let outputPixelSize: PixelSize
    public let shouldMute: Bool
    public let quality: ExportQuality

    public init(
        inputFileURL: URL,
        outputFileURL: URL,
        presetName: String,
        outputFileType: AVFileType?,
        timeRange: CMTimeRange,
        outputPixelSize: PixelSize,
        shouldMute: Bool,
        quality: ExportQuality
    ) {
        self.inputFileURL = inputFileURL
        self.outputFileURL = outputFileURL
        self.presetName = presetName
        self.outputFileType = outputFileType
        self.timeRange = timeRange
        self.outputPixelSize = outputPixelSize
        self.shouldMute = shouldMute
        self.quality = quality
    }
}

public struct AVFoundationExportPlanFactory: Sendable {
    public init() {}

    public func makePlan(
        for request: ExportRequest,
        outputFileURL: URL
    ) throws -> AVFoundationExportPlan {
        try AVFoundationExportPlan(
            inputFileURL: request.inputFileURL,
            outputFileURL: outputFileURL,
            presetName: presetName(for: request.format, quality: request.resolvedQuality),
            outputFileType: outputFileType(for: request.format),
            timeRange: CMTimeRange(
                start: CMTime(seconds: request.timeRange.start, preferredTimescale: 600),
                duration: CMTime(seconds: request.timeRange.duration, preferredTimescale: 600)
            ),
            outputPixelSize: request.outputPixelSize,
            shouldMute: request.outputShouldMute,
            quality: request.resolvedQuality
        )
    }

    private func presetName(for format: ExportFormat, quality: ExportQuality) throws -> String {
        switch format {
        case .m4a:
            AVAssetExportPresetAppleM4A
        case .alac, .wav, .caf, .flac:
            AVAssetExportPresetPassthrough
        case .mp4:
            switch quality {
            case .compact:
                AVAssetExportPresetMediumQuality
            case .balanced, .high, .lossless:
                AVAssetExportPresetHighestQuality
            }
        case .hevc:
            AVAssetExportPresetHEVCHighestQuality
        case .av1, .webm, .gif, .apng:
            throw AVFoundationExportPlanError.unsupportedFormat(format)
        }
    }

    private func outputFileType(for format: ExportFormat) throws -> AVFileType? {
        switch format {
        case .m4a:
            .m4a
        case .alac:
            .m4a
        case .wav:
            .wav
        case .caf:
            .caf
        case .flac:
            nil
        case .mp4, .hevc:
            .mp4
        case .av1, .webm, .gif, .apng:
            throw AVFoundationExportPlanError.unsupportedFormat(format)
        }
    }
}

public enum AVFoundationExportPlanError: Error, Equatable {
    case unsupportedFormat(ExportFormat)
}
