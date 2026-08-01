import Foundation
import LuxelCore

public struct WebMMediaExporter: MediaExporter, Sendable {
    public init() {}

    public func export(
        _ input: MediaExportInput,
        to outputFileURL: URL,
        progress: MediaExportProgressHandler?
    ) async throws -> ExportedMedia {
        let request = input.request
        guard request.format == .webm else {
            throw WebMCodecError.unsupportedFormat(request.format)
        }

        return try await CodecExportPipeline(
            mediaSource: AVAssetReaderCodecMediaSource(),
            videoEncoder: VPXVideoEncoder(),
            audioEncoder: OpusAudioEncoder(),
            muxer: WebMMuxer()
        ).export(input, to: outputFileURL, progress: progress)
    }
}

public struct WebMExportSizeEstimator: ExportSizeEstimator, Sendable {
    public init() {}

    public func estimate(_ request: ExportRequest) async throws -> ExportEstimate {
        guard request.format == .webm else {
            throw WebMCodecError.unsupportedFormat(request.format)
        }

        let bitsPerPixel =
            switch request.resolvedQuality {
            case .compact:
                0.035
            case .balanced, .lossless:
                0.055
            case .high:
                0.085
            }
        return try ModeledExportSizeEstimator.estimate(
            request,
            bitsPerPixel: bitsPerPixel,
            audioBitsPerSecond: WebMOpusBitrate.balanced
        )
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
