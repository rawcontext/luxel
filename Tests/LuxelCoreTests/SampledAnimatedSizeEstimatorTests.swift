import Foundation
import Testing
@testable import LuxelCore

@Suite("Sampled animated size estimator")
struct SampledAnimatedSizeEstimatorTests {
    @Test("estimate model applies adjacent-frame correction")
    func estimateModelAppliesAdjacentFrameCorrection() throws {
        let model = try SampledAnimatedEstimateModel(
            totalFrameCount: 10,
            sampleByteCounts: [900, 1_000, 1_100],
            adjacentPairs: [
                SampledAnimatedAdjacentPairSize(
                    firstBytes: 1_000,
                    secondBytes: 1_000,
                    combinedBytes: 1_000
                ),
                SampledAnimatedAdjacentPairSize(
                    firstBytes: 1_000,
                    secondBytes: 1_000,
                    combinedBytes: 1_800
                )
            ]
        )

        #expect(model.estimatedByteCount == 7_000)
    }

    @Test("estimate model rejects invalid samples")
    func estimateModelRejectsInvalidSamples() {
        #expect(throws: SampledAnimatedSizeEstimatorError.invalidSampleData) {
            _ = try SampledAnimatedEstimateModel(
                totalFrameCount: 10,
                sampleByteCounts: [],
                adjacentPairs: []
            )
        }
    }

    @Test("sampled estimator rejects movie formats")
    func sampledEstimatorRejectsMovieFormats() async throws {
        let request = try makeRequest(format: .mp4)

        await #expect(throws: SampledAnimatedSizeEstimatorError.unsupportedFormat(.mp4)) {
            _ = try await SampledAnimatedSizeEstimator().estimate(request)
        }
    }

    @Test("gif estimate stays within tolerance of actual export")
    func gifEstimateStaysWithinToleranceOfActualExport() async throws {
        let outputURL = temporaryOutputURL(fileExtension: "gif")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }
        let request = try makeRequest(
            format: .gif,
            pixelSize: PixelSize(width: 160, height: 90)
        )

        let estimate = try await SampledAnimatedSizeEstimator().estimate(request)
        _ = try await ImageIOAnimatedMediaExporter().export(request, to: outputURL)
        let actualBytes = try fileSize(at: outputURL)

        #expect(estimate.confidence == .sampled)
        #expect(isWithinRelativeTolerance(estimate.bytes, actualBytes, tolerance: 0.35))
    }

    @Test("apng estimate returns sampled confidence")
    func apngEstimateReturnsSampledConfidence() async throws {
        let request = try makeRequest(
            format: .apng,
            pixelSize: PixelSize(width: 160, height: 90)
        )

        let estimate = try await SampledAnimatedSizeEstimator().estimate(request)

        #expect(estimate.confidence == .sampled)
        #expect(estimate.bytes > 0)
    }

    @Test("native estimator routes movies and rejects future codecs")
    func nativeEstimatorRoutesMoviesAndRejectsFutureCodecs() async throws {
        let mp4Request = try makeRequest(format: .mp4)
        let webMRequest = try makeRequest(format: .webm)
        let estimate = try await NativeExportSizeEstimator().estimate(mp4Request)
        let expected = try await BitrateModelSizeEstimator().estimate(mp4Request)

        #expect(estimate == expected)
        await #expect(throws: NativeExportSizeEstimatorError.unsupportedFormat(.webm)) {
            _ = try await NativeExportSizeEstimator().estimate(webMRequest)
        }
    }

    private func makeRequest(
        format: ExportFormat,
        pixelSize: PixelSize? = nil
    ) throws -> ExportRequest {
        try ExportRequest(
            inputFileURL: fixtureURL("input.mp4"),
            format: format,
            pixelSize: pixelSize ?? PixelSize(width: 160, height: 90),
            frameRate: FrameRate(10),
            timeRange: TimeRange(start: 1, end: 1.3),
            shouldMute: false,
            shouldCrop: true
        )
    }

    private func fileSize(at fileURL: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = try #require(attributes[.size] as? NSNumber)
        return size.int64Value
    }

    private func isWithinRelativeTolerance(
        _ estimate: Int64,
        _ actual: Int64,
        tolerance: Double
    ) -> Bool {
        let delta = abs(Double(estimate - actual))
        return delta / Double(actual) <= tolerance
    }

    private func fixtureURL(_ fileName: String) throws -> URL {
        try packageRootURL()
            .appending(path: "docs/Luxel/test/fixtures")
            .appending(path: fileName)
    }

    private func temporaryOutputURL(fileExtension: String) -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "luxel-sampled-estimate-\(UUID().uuidString)")
            .appendingPathExtension(fileExtension)
    }

    private func packageRootURL() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.lastPathComponent != "Tests" {
            let next = url.deletingLastPathComponent()
            try #require(next.path != url.path)
            url = next
        }

        return url.deletingLastPathComponent()
    }
}
