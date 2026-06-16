import Foundation
import LuxelCore

public struct WebMMediaExporter: MediaExporter, Sendable {
    public init() {}

    public func export(
        _ request: ExportRequest,
        to outputFileURL: URL,
        progress: MediaExportProgressHandler?
    ) async throws -> ExportedMedia {
        guard request.format == .webm else {
            throw WebMCodecError.unsupportedFormat(request.format)
        }

        return try await CodecExportPipeline(
            mediaSource: AVAssetReaderCodecMediaSource(),
            videoEncoder: VPXVideoEncoder(),
            audioEncoder: OpusAudioEncoder(),
            muxer: WebMMuxer()
        ).export(request, to: outputFileURL, progress: progress)
    }
}

public struct WebMExportSizeEstimator: ExportSizeEstimator, Sendable {
    public init() {}

    public func estimate(_ request: ExportRequest) async throws -> ExportEstimate {
        guard request.format == .webm else {
            throw WebMCodecError.unsupportedFormat(request.format)
        }

        let outputPixelSize = try request.outputPixelSize
        let bitsPerPixel = switch request.resolvedQuality {
        case .compact:
            0.035
        case .balanced, .lossless:
            0.055
        case .high:
            0.085
        }
        let pixelRate = Double(outputPixelSize.width * outputPixelSize.height * request.frameRate.framesPerSecond)
        let videoBitsPerSecond = pixelRate * bitsPerPixel
        let audioBitsPerSecond = request.outputShouldMute ? 0 : Double(WebMOpusBitrate.balanced)
        let containerOverhead = 1.02
        let bytes = Int64((((videoBitsPerSecond + audioBitsPerSecond) * request.outputDuration) / 8 * containerOverhead).rounded(.up))

        return try ExportEstimate(bytes: bytes, confidence: .modeled)
    }
}

public enum WebMCodecAdapter {
    public static func registration() throws -> CodecAdapterRegistration {
        try CodecAdapterRegistration(
            format: .webm,
            exporter: WebMMediaExporter(),
            sizeEstimator: WebMExportSizeEstimator()
        )
    }
}

private enum WebMOpusBitrate {
    static let balanced = 128_000
}
