public enum ModeledExportSizeEstimator {
    public static func estimate(
        _ request: ExportRequest,
        bitsPerPixel: Double,
        audioBitsPerSecond: Int,
        containerOverhead: Double = 1.02
    ) throws -> ExportEstimate {
        let size = try request.outputPixelSize
        let pixelRate = Double(size.width * size.height * request.frameRate.framesPerSecond)
        let videoBitsPerSecond = pixelRate * bitsPerPixel
        let audioBits = request.outputShouldMute ? 0 : Double(audioBitsPerSecond)
        let bytes = Int64(
            (((videoBitsPerSecond + audioBits) * request.outputDuration) / 8 * containerOverhead)
                .rounded(.up)
        )
        return try ExportEstimate(bytes: bytes, confidence: .modeled)
    }
}
