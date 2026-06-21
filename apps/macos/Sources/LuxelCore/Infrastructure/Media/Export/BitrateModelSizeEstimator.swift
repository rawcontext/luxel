import Foundation

public struct BitrateModelSizeEstimator: ExportSizeEstimator, Sendable {
    private let audioBitsPerSecond: Int

    public init(audioBitsPerSecond: Int = 128_000) {
        self.audioBitsPerSecond = audioBitsPerSecond
    }

    public func estimate(_ request: ExportRequest) async throws -> ExportEstimate {
        if request.format.isAudioOnlyFormat {
            let bitsPerSecond = audioOnlyBitsPerSecond(for: request.format)
            let bytes = Int64((Double(bitsPerSecond) * request.outputDuration / 8).rounded(.up))
            return try ExportEstimate(bytes: bytes, confidence: .modeled)
        }

        guard let videoBitsPerPixel = request.resolvedQuality.videoBitsPerPixel(for: request.format)
        else {
            throw BitrateModelSizeEstimatorError.unsupportedFormat(request.format)
        }

        let outputPixelSize = try request.outputPixelSize
        let pixelRate = Double(
            outputPixelSize.width * outputPixelSize.height * request.frameRate.framesPerSecond)
        let videoBitsPerSecond = pixelRate * videoBitsPerPixel
        let audioBits = request.outputShouldMute ? 0 : Double(audioBitsPerSecond)
        let totalBits = (videoBitsPerSecond + audioBits) * request.outputDuration
        let bytes = Int64((totalBits / 8).rounded(.up))

        return try ExportEstimate(bytes: bytes, confidence: .modeled)
    }

    private func audioOnlyBitsPerSecond(for format: ExportFormat) -> Int {
        switch format {
        case .m4a:
            audioBitsPerSecond
        case .alac, .flac:
            768_000
        case .wav, .caf:
            1_536_000
        case .mp4, .hevc, .gif, .webm, .apng, .av1:
            audioBitsPerSecond
        }
    }
}

public enum BitrateModelSizeEstimatorError: Error, Equatable {
    case unsupportedFormat(ExportFormat)
}
