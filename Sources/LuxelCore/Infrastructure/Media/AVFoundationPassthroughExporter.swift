import AVFoundation
import CoreMedia
import Foundation

public struct AVFoundationPassthroughExporter: PassthroughExporter, Sendable {
    public init() {}

    public func export(_ request: PassthroughExportRequest) async throws -> PassthroughExportResult {
        guard let timeRange = request.timeRange else {
            throw AVFoundationPassthroughExporterError.missingTimeRange
        }

        let outputFileType = try outputFileType(for: request.outputFileURL)
        let asset = AVURLAsset(url: request.inputFileURL)

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetPassthrough
        ) else {
            throw AVFoundationPassthroughExporterError.unsupportedPreset(AVAssetExportPresetPassthrough)
        }

        guard exportSession.supportedFileTypes.contains(outputFileType) else {
            throw AVFoundationPassthroughExporterError.unsupportedOutputFileType(outputFileType.rawValue)
        }

        exportSession.timeRange = CMTimeRange(
            start: CMTime(seconds: timeRange.start, preferredTimescale: 600),
            duration: CMTime(seconds: timeRange.duration, preferredTimescale: 600)
        )
        exportSession.shouldOptimizeForNetworkUse = true

        try FileManager.default.createDirectory(
            at: request.outputFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: request.outputFileURL)

        do {
            try await exportSession.export(to: request.outputFileURL, as: outputFileType)
        } catch {
            try? FileManager.default.removeItem(at: request.outputFileURL)
            throw error
        }

        return PassthroughExportResult(fileURL: request.outputFileURL)
    }

    private func outputFileType(for fileURL: URL) throws -> AVFileType {
        switch fileURL.pathExtension.lowercased() {
        case "m4a":
            .m4a
        case "mov", "qt":
            .mov
        case "mp4", "m4v", "":
            .mp4
        default:
            throw AVFoundationPassthroughExporterError.unsupportedPathExtension(fileURL.pathExtension)
        }
    }
}

public enum AVFoundationPassthroughExporterError: Error, Equatable {
    case missingTimeRange
    case unsupportedPathExtension(String)
    case unsupportedPreset(String)
    case unsupportedOutputFileType(String)
}
