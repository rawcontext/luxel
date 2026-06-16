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

    @Test("gif estimate matches native export for fully sampled clips")
    func gifEstimateMatchesNativeExportForFullySampledClips() async throws {
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
        #expect(estimate.bytes == actualBytes)
    }

    @Test("gif estimate cache keys include render options")
    func gifEstimateCacheKeysIncludeRenderOptions() async throws {
        let outputURL = temporaryOutputURL(fileExtension: "gif")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }
        let estimator = SampledAnimatedSizeEstimator()
        let baseRequest = try makeRequest(
            format: .gif,
            gifOptions: GIFRenderOptions(
                quality: .balanced,
                loopMode: .forever,
                dithering: .none
            )
        )
        let bounceRequest = try makeRequest(
            format: .gif,
            gifOptions: GIFRenderOptions(
                quality: .balanced,
                loopMode: .bounce,
                dithering: .none
            )
        )

        let baseEstimate = try await estimator.estimate(baseRequest)
        let bounceEstimate = try await estimator.estimate(bounceRequest)
        _ = try await ImageIOAnimatedMediaExporter().export(bounceRequest, to: outputURL)
        let actualBounceBytes = try fileSize(at: outputURL)

        #expect(bounceEstimate.bytes > baseEstimate.bytes)
        #expect(bounceEstimate.bytes == actualBounceBytes)
    }

    @Test("gif estimate cache keys include zoom blocks")
    func gifEstimateCacheKeysIncludeZoomBlocks() async throws {
        let outputURL = temporaryOutputURL(fileExtension: "gif")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }
        let estimator = SampledAnimatedSizeEstimator()
        let baseRequest = try makeRequest(format: .gif)
        let zoomRequest = try makeRequest(
            format: .gif,
            zoomBlocks: [
                zoomBlock(start: 1, end: 1.3)
            ]
        )

        _ = try await estimator.estimate(baseRequest)
        let zoomEstimate = try await estimator.estimate(zoomRequest)
        _ = try await ImageIOAnimatedMediaExporter().export(zoomRequest, to: outputURL)
        let actualZoomBytes = try fileSize(at: outputURL)

        #expect(zoomEstimate.bytes == actualZoomBytes)
    }

    @Test("gif estimates preserve size and quality budgets")
    func gifEstimatesPreserveSizeAndQualityBudgets() async throws {
        let estimator = SampledAnimatedSizeEstimator()
        let balancedLarge = try await estimator.estimate(try makeRequest(
            format: .gif,
            pixelSize: PixelSize(width: 160, height: 90),
            quality: .balanced
        ))
        let balancedSmall = try await estimator.estimate(try makeRequest(
            format: .gif,
            pixelSize: PixelSize(width: 80, height: 45),
            quality: .balanced
        ))
        let compactLarge = try await estimator.estimate(try makeRequest(
            format: .gif,
            pixelSize: PixelSize(width: 160, height: 90),
            quality: .compact
        ))

        #expect(balancedSmall.bytes < balancedLarge.bytes)
        #expect(compactLarge.bytes <= balancedLarge.bytes)
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

    @Test("apng estimate matches native export for zoomed fully sampled clips")
    func apngEstimateMatchesNativeExportForZoomedFullySampledClips() async throws {
        let outputURL = temporaryOutputURL(fileExtension: "apng")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }
        let request = try makeRequest(
            format: .apng,
            pixelSize: PixelSize(width: 160, height: 90),
            zoomBlocks: [
                zoomBlock(start: 1, end: 1.3)
            ]
        )

        let estimate = try await SampledAnimatedSizeEstimator().estimate(request)
        _ = try await ImageIOAnimatedMediaExporter().export(request, to: outputURL)
        let actualBytes = try fileSize(at: outputURL)

        #expect(estimate.confidence == .sampled)
        #expect(estimate.bytes == actualBytes)
    }

    @Test("apng estimate cache keys include loop options")
    func apngEstimateCacheKeysIncludeLoopOptions() async throws {
        let outputURL = temporaryOutputURL(fileExtension: "apng")
        defer {
            try? FileManager.default.removeItem(at: outputURL)
        }
        let estimator = SampledAnimatedSizeEstimator()
        let baseRequest = try makeRequest(
            format: .apng,
            gifOptions: GIFRenderOptions(loopMode: .forever)
        )
        let bounceRequest = try makeRequest(
            format: .apng,
            gifOptions: GIFRenderOptions(loopMode: .bounce)
        )

        let baseEstimate = try await estimator.estimate(baseRequest)
        let bounceEstimate = try await estimator.estimate(bounceRequest)
        _ = try await ImageIOAnimatedMediaExporter().export(bounceRequest, to: outputURL)
        let actualBounceBytes = try fileSize(at: outputURL)

        #expect(bounceEstimate.bytes > baseEstimate.bytes)
        #expect(bounceEstimate.bytes == actualBounceBytes)
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
        pixelSize: PixelSize? = nil,
        quality: ExportQuality = .balanced,
        gifOptions: GIFRenderOptions? = nil,
        zoomBlocks: [ZoomBlock] = []
    ) throws -> ExportRequest {
        try ExportRequest(
            inputFileURL: fixtureURL("input.mp4"),
            format: format,
            pixelSize: pixelSize ?? PixelSize(width: 160, height: 90),
            frameRate: FrameRate(10),
            timeRange: TimeRange(start: 1, end: 1.3),
            shouldMute: false,
            shouldCrop: true,
            quality: quality,
            gifOptions: gifOptions,
            zoomBlocks: zoomBlocks
        )
    }

    private func zoomBlock(start: TimeInterval, end: TimeInterval) throws -> ZoomBlock {
        try ZoomBlock(
            timeRange: TimeRange(start: start, end: end),
            targetRect: NormalizedRect(x: 0.25, y: 0.25, width: 0.2, height: 0.2),
            zoom: 2,
            transitionOverride: 0.05
        )
    }

    private func fileSize(at fileURL: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let size = try #require(attributes[.size] as? NSNumber)
        return size.int64Value
    }

    private func fixtureURL(_ fileName: String) throws -> URL {
        try packageRootURL()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
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
