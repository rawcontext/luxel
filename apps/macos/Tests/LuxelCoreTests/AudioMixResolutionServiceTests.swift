import Foundation
import LuxelCore
import LuxelTestSupport
import Testing

@Suite("Audio mix resolution service")
struct AudioMixResolutionServiceTests {
    @Test("default mix uses source audio tracks without analysis")
    func defaultMixUsesSourceAudioTracksWithoutAnalysis() async throws {
        let analyzer = SpyAudioPeakAnalyzer()
        let service = AudioMixResolutionService(analyzer: analyzer)
        let draft = EditorExportDraft(
            source: try makeSource(audioTracks: [.system, .microphone]),
            format: .mp4
        )

        let gains = try await service.resolvedGains(for: draft)

        #expect(gains == [.system: 1, .microphone: 1])
        #expect(await analyzer.requests().isEmpty)
    }

    @Test("non-normalized explicit mix resolves without analysis")
    func nonNormalizedExplicitMixResolvesWithoutAnalysis() async throws {
        let analyzer = SpyAudioPeakAnalyzer()
        let service = AudioMixResolutionService(analyzer: analyzer)
        let request = try makeRequest(
            audioMix: AudioMixPlan(tracks: [
                AudioTrackMix(kind: .system, volume: 0.5),
                AudioTrackMix(kind: .microphone, volume: 1.5, isMuted: true)
            ])
        )

        let gains = try await service.resolvedGains(
            for: request,
            sourceAudioTracks: [.system, .microphone]
        )

        #expect(gains == [.system: 0.5, .microphone: 0])
        #expect(await analyzer.requests().isEmpty)
    }

    @Test("normalized mix analyzes audible source tracks")
    func normalizedMixAnalyzesAudibleSourceTracks() async throws {
        let analyzer = SpyAudioPeakAnalyzer(peaks: [.system: 0.4])
        let service = AudioMixResolutionService(analyzer: analyzer)
        let timeRange = try TimeRange(start: 2, end: 8)
        let request = try makeRequest(
            timeRange: timeRange,
            audioMix: AudioMixPlan(
                tracks: [
                    AudioTrackMix(kind: .system, volume: 0.5),
                    AudioTrackMix(kind: .microphone, volume: 1.25, isMuted: true)
                ],
                normalizePeak: true
            )
        )

        let gains = try await service.resolvedGains(
            for: request,
            sourceAudioTracks: [.system, .microphone]
        )

        #expect(isApproximately(gains[.system], AudioMixPlan.normalizationTargetPeak / 0.4))
        #expect(isApproximately(gains[.microphone], 0))
        #expect(
            await analyzer.requests() == [
                AudioPeakAnalysisRequest(
                    inputFileURL: URL(fileURLWithPath: "/tmp/input.mp4"),
                    timeRange: timeRange,
                    audioTracks: [.system]
                )
            ])
    }

    @Test("normalization skips unavailable mix tracks")
    func normalizationSkipsUnavailableMixTracks() async throws {
        let analyzer = SpyAudioPeakAnalyzer(peaks: [.system: 0.8])
        let service = AudioMixResolutionService(analyzer: analyzer)
        let request = try makeRequest(
            audioMix: AudioMixPlan(
                tracks: [
                    AudioTrackMix(kind: .system),
                    AudioTrackMix(kind: .microphone)
                ],
                normalizePeak: true
            )
        )

        _ = try await service.resolvedGains(
            for: request,
            sourceAudioTracks: [.system]
        )

        #expect(await analyzer.requests().map(\.audioTracks) == [[.system]])
    }

    @Test("muted and audio-dropping exports do not analyze")
    func mutedAndAudioDroppingExportsDoNotAnalyze() async throws {
        let analyzer = SpyAudioPeakAnalyzer()
        let service = AudioMixResolutionService(analyzer: analyzer)
        let mutedRequest = try makeRequest(
            shouldMute: true,
            audioMix: AudioMixPlan(
                tracks: [AudioTrackMix(kind: .system)],
                normalizePeak: true
            )
        )
        let gifRequest = try makeRequest(
            format: .gif,
            audioMix: AudioMixPlan(
                tracks: [AudioTrackMix(kind: .system)],
                normalizePeak: true
            )
        )

        let mutedGains = try await service.resolvedGains(
            for: mutedRequest,
            sourceAudioTracks: [.system]
        )
        let gifGains = try await service.resolvedGains(
            for: gifRequest,
            sourceAudioTracks: [.system]
        )

        #expect(mutedGains == [.system: 0])
        #expect(gifGains == [.system: 0])
        #expect(await analyzer.requests().isEmpty)
    }

    private func makeSource(audioTracks: [AudioTrackKind]) throws -> SourceMedia {
        try SourceMedia(
            fileURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            duration: 10,
            pixelSize: PixelSize(width: 640, height: 480),
            nominalFrameRate: FrameRate(30),
            hasAudio: !audioTracks.isEmpty,
            audioTracks: audioTracks
        )
    }

    private func makeRequest(
        format: ExportFormat = .mp4,
        timeRange: TimeRange? = nil,
        shouldMute: Bool = false,
        audioMix: AudioMixPlan? = nil
    ) throws -> ExportRequest {
        try ExportRequest(
            inputFileURL: URL(fileURLWithPath: "/tmp/input.mp4"),
            format: format,
            pixelSize: PixelSize(width: 640, height: 480),
            frameRate: FrameRate(30),
            timeRange: timeRange ?? TimeRange(start: 0, end: 10),
            shouldMute: shouldMute,
            audioMix: audioMix,
            shouldCrop: false
        )
    }

    private func isApproximately(
        _ lhs: Double?,
        _ rhs: Double,
        tolerance: Double = 0.000_001
    ) -> Bool {
        guard let lhs else {
            return false
        }

        return abs(lhs - rhs) <= tolerance
    }
}

private typealias SpyAudioPeakAnalyzer = TestAudioPeakAnalyzerSpy
