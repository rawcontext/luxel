import Foundation
import LuxelCore

public struct AV1MediaExporter: MediaExporter, Sendable {
    public init() {}

    public func export(
        _ input: MediaExportInput,
        to outputFileURL: URL,
        progress: MediaExportProgressHandler?
    ) async throws -> ExportedMedia {
        let request = input.request
        guard request.format == .av1 else {
            throw AV1CodecError.unsupportedFormat(request.format)
        }

        return try await CodecExportPipeline(
            mediaSource: AVAssetReaderCodecMediaSource(),
            videoEncoder: SVTAV1VideoEncoder(),
            audioEncoder: PCM16AudioPassthroughEncoder(),
            muxer: AV1MP4Muxer()
        ).export(input, to: outputFileURL, progress: progress)
    }
}

public struct AV1ExportSizeEstimator: ExportSizeEstimator, Sendable {
    public init() {}

    public func estimate(_ request: ExportRequest) async throws -> ExportEstimate {
        guard request.format == .av1 else {
            throw AV1CodecError.unsupportedFormat(request.format)
        }

        let bitsPerPixel =
            switch request.resolvedQuality {
            case .compact:
                0.025
            case .balanced, .lossless:
                0.04
            case .high:
                0.065
            }
        return try ModeledExportSizeEstimator.estimate(
            request,
            bitsPerPixel: bitsPerPixel,
            audioBitsPerSecond: AV1AACBitrate.balanced
        )
    }
}

public enum AV1CodecAdapter {
    public static func registration() throws -> CodecAdapterRegistration {
        try CodecAdapterRegistration(
            format: .av1,
            exporter: AV1MediaExporter(),
            sizeEstimator: AV1ExportSizeEstimator()
        )
    }
}

public actor PCM16AudioPassthroughEncoder: CodecAudioEncoder {
    private var configuration: CodecAudioEncoderConfiguration?

    public init() {}

    public func prepare(_ configuration: CodecAudioEncoderConfiguration) async throws {
        guard configuration.sampleRate == 48_000, configuration.channelCount == 2 else {
            throw AV1CodecError.invalidConfiguration("AV1 audio export expects 48 kHz stereo PCM.")
        }

        self.configuration = configuration
    }

    public func encode(chunk: CodecAudioChunk) async throws -> [EncodedPacket] {
        guard configuration != nil else {
            throw AV1CodecError.invalidConfiguration("PCM audio encoder was used before prepare.")
        }

        return [
            try EncodedPacket(
                data: chunk.pcmData,
                presentationTime: chunk.presentationTime,
                duration: chunk.duration,
                isKeyFrame: true
            )
        ]
    }

    public func finish() async throws -> [EncodedPacket] {
        []
    }
}

private enum AV1AACBitrate {
    static let balanced = 128_000
}
