import Foundation
import LuxelCore
import LuxelTestSupport
import Testing

@Suite("Bitrate model size estimator")
struct BitrateModelSizeEstimatorTests {
    @Test("estimates movie bytes from quality mapping and audio bitrate")
    func estimatesMovieBytes() async throws {
        let request = try makeRequest(
            format: .mp4,
            width: 100,
            height: 200,
            frameRate: 10,
            timeRange: TimeRange(start: 1, end: 5),
            quality: .balanced,
            shouldMute: false
        )

        let estimate = try await BitrateModelSizeEstimator().estimate(request)
        let expected = try ExportEstimate(bytes: 76_000, confidence: .modeled)

        #expect(estimate == expected)
    }

    @Test("drops audio bitrate when output is muted")
    func dropsAudioBitrateWhenMuted() async throws {
        let request = try makeRequest(
            format: .mp4,
            width: 100,
            height: 200,
            frameRate: 10,
            timeRange: TimeRange(start: 1, end: 5),
            quality: .balanced,
            shouldMute: true
        )

        let estimate = try await BitrateModelSizeEstimator().estimate(request)
        let expected = try ExportEstimate(bytes: 12_000, confidence: .modeled)

        #expect(estimate == expected)
    }

    @Test("uses playback-adjusted output duration")
    func usesPlaybackAdjustedOutputDuration() async throws {
        let request = try makeRequest(
            format: .mp4,
            width: 100,
            height: 200,
            frameRate: 10,
            timeRange: TimeRange(start: 1, end: 5),
            quality: .balanced,
            shouldMute: false,
            speed: PlaybackSpeed(2)
        )

        let estimate = try await BitrateModelSizeEstimator().estimate(request)
        let expected = try ExportEstimate(bytes: 38_000, confidence: .modeled)

        #expect(estimate == expected)
    }

    @Test("estimates ProRes movie bytes")
    func estimatesProResMovieBytes() async throws {
        let expectations: [(format: ExportFormat, bytes: Int64)] = [
            (.proRes422, 299_000),
            (.proRes4444, 594_000)
        ]

        for expectation in expectations {
            let request = try makeRequest(
                format: expectation.format,
                width: 100,
                height: 200,
                frameRate: 10,
                timeRange: TimeRange(start: 1, end: 5),
                quality: .high,
                shouldMute: false
            )

            let estimate = try await BitrateModelSizeEstimator().estimate(request)
            let expected = try ExportEstimate(bytes: expectation.bytes, confidence: .modeled)

            #expect(estimate == expected)
        }
    }

    @Test("estimates audio-only bytes by native format")
    func estimatesAudioOnlyBytesByNativeFormat() async throws {
        let expectations: [(format: ExportFormat, bytes: Int64)] = [
            (.m4a, 16_000),
            (.alac, 96_000),
            (.wav, 192_000),
            (.caf, 192_000),
            (.flac, 96_000)
        ]

        for expectation in expectations {
            let request = try makeRequest(
                format: expectation.format, timeRange: TimeRange(start: 0, end: 1))

            let estimate = try await BitrateModelSizeEstimator().estimate(request)
            let expected = try ExportEstimate(bytes: expectation.bytes, confidence: .modeled)

            #expect(estimate == expected)
        }
    }

    @Test("rounds video dimensions before estimating")
    func roundsVideoDimensionsBeforeEstimating() async throws {
        let request = try makeRequest(
            format: .hevc,
            width: 101,
            height: 201,
            frameRate: 10,
            timeRange: TimeRange(start: 0, end: 1),
            quality: .compact,
            shouldMute: true
        )

        let estimate = try await BitrateModelSizeEstimator().estimate(request)
        let expected = try ExportEstimate(bytes: 1_288, confidence: .modeled)

        #expect(estimate == expected)
    }

    @Test("rejects formats without arithmetic bitrate model")
    func rejectsFormatsWithoutArithmeticModel() async throws {
        let request = try makeRequest(format: .gif)

        await #expect(throws: BitrateModelSizeEstimatorError.unsupportedFormat(.gif)) {
            _ = try await BitrateModelSizeEstimator().estimate(request)
        }
    }

    @Test("service resolves draft before estimating")
    func serviceResolvesDraftBeforeEstimating() async throws {
        let estimator = SpyExportSizeEstimator()
        let service = ExportSizeEstimationService(estimator: estimator)
        let source = try SourceMedia(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            duration: 8,
            pixelSize: PixelSize(width: 640, height: 480),
            nominalFrameRate: FrameRate(30),
            hasAudio: true
        )
        let draft = try EditorExportDraft(
            source: source,
            format: .hevc,
            quality: .high,
            speed: PlaybackSpeed(2),
            pixelSize: PixelSize(width: 320, height: 240),
            frameRate: FrameRate(24),
            trimRange: TimeRange(start: 2, end: 6),
            shouldMute: true
        )

        let estimate = try await service.estimate(draft)
        let captured = await estimator.request()
        let expectedEstimate = try ExportEstimate(bytes: 42, confidence: .modeled)
        let expectedRange = try TimeRange(start: 2, end: 6)
        let expectedPixelSize = try PixelSize(width: 320, height: 240)
        let expectedFrameRate = try FrameRate(24)

        #expect(estimate == expectedEstimate)
        expectTestExportRequest(
            captured,
            expected: TestExportRequestExpectation(
                format: .hevc,
                timeRange: expectedRange,
                pixelSize: expectedPixelSize,
                frameRate: expectedFrameRate,
                shouldMute: true,
                quality: .high,
                speed: try PlaybackSpeed(2)
            )
        )
    }

    private func makeRequest(
        format: ExportFormat,
        width: Int = 100,
        height: Int = 200,
        frameRate: Int = 10,
        timeRange: TimeRange? = nil,
        quality: ExportQuality = .balanced,
        shouldMute: Bool = false,
        speed: PlaybackSpeed = .normal
    ) throws -> ExportRequest {
        try ExportRequest(
            inputFileURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            format: format,
            pixelSize: PixelSize(width: width, height: height),
            frameRate: FrameRate(frameRate),
            timeRange: timeRange ?? TimeRange(start: 0, end: 1),
            shouldMute: shouldMute,
            shouldCrop: false,
            quality: quality,
            speed: speed
        )
    }
}

private actor SpyExportSizeEstimator: ExportSizeEstimator {
    private var capturedRequest: ExportRequest?

    func estimate(_ request: ExportRequest) async throws -> ExportEstimate {
        capturedRequest = request
        return try ExportEstimate(bytes: 42, confidence: .modeled)
    }

    func request() -> ExportRequest? {
        capturedRequest
    }
}
