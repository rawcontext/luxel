import Foundation

public struct BitrateModelSizeEstimator: ExportSizeEstimator, Sendable {
    private let audioBitsPerSecond: Int

    public init(audioBitsPerSecond: Int = 128_000) {
        self.audioBitsPerSecond = audioBitsPerSecond
    }

    public func estimate(_ request: ExportRequest) async throws -> ExportEstimate {
        guard let videoBitsPerPixel = request.resolvedQuality.videoBitsPerPixel(for: request.format) else {
            throw BitrateModelSizeEstimatorError.unsupportedFormat(request.format)
        }

        let outputPixelSize = try request.outputPixelSize
        let pixelRate = Double(outputPixelSize.width * outputPixelSize.height * request.frameRate.framesPerSecond)
        let videoBitsPerSecond = pixelRate * videoBitsPerPixel
        let audioBits = request.outputShouldMute ? 0 : Double(audioBitsPerSecond)
        let totalBits = (videoBitsPerSecond + audioBits) * request.outputDuration
        let bytes = Int64((totalBits / 8).rounded(.up))

        return try ExportEstimate(bytes: bytes, confidence: .modeled)
    }
}

public enum BitrateModelSizeEstimatorError: Error, Equatable {
    case unsupportedFormat(ExportFormat)
}
