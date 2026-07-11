import Foundation

public struct AudioMixResolutionService: Sendable {
    private let analyzer: any AudioPeakAnalyzer

    public init(analyzer: any AudioPeakAnalyzer) {
        self.analyzer = analyzer
    }

    public func resolvedGains(for draft: EditorExportDraft) async throws -> [AudioTrackKind: Double] {
        try await resolvedGains(
            for: try draft.exportRequest,
            sourceAudioTracks: draft.source.audioTracks
        )
    }

    public func resolvedGains(
        for request: ExportRequest,
        sourceAudioTracks: [AudioTrackKind]
    ) async throws -> [AudioTrackKind: Double] {
        let sourceAudioTracks = Self.deduplicated(sourceAudioTracks)
        let mixPlan = request.audioMix ?? Self.defaultMixPlan(for: sourceAudioTracks)

        guard !request.outputShouldMute else {
            return mutedGains(for: mixPlan)
        }

        guard mixPlan.normalizePeak else {
            return mixPlan.resolvedGains()
        }

        let audioTracksToAnalyze = audibleSourceAudioTracks(
            in: mixPlan,
            sourceAudioTracks: sourceAudioTracks
        )
        guard !audioTracksToAnalyze.isEmpty else {
            return mixPlan.resolvedGains()
        }

        let measuredPeaks = try await analyzer.measurePeaks(
            AudioPeakAnalysisRequest(
                inputFileURL: request.inputFileURL,
                timeRange: request.timeRange,
                editPlan: request.editPlan,
                audioTracks: audioTracksToAnalyze
            ))
        return mixPlan.resolvedGains(measuredPeaks: measuredPeaks)
    }

    public func resolvedGains(
        for request: ExportRequest,
        measuredPeaks: [AudioTrackKind: Double]
    ) -> [AudioTrackKind: Double] {
        let mixPlan = request.audioMix ?? AudioMixPlan(
            tracks: [AudioTrackMix(kind: .system)]
        )
        guard !request.outputShouldMute else {
            return mutedGains(for: mixPlan)
        }

        return mixPlan.resolvedGains(measuredPeaks: measuredPeaks)
    }

    private static func defaultMixPlan(for sourceAudioTracks: [AudioTrackKind]) -> AudioMixPlan {
        AudioMixPlan(tracks: sourceAudioTracks.map { AudioTrackMix(kind: $0) })
    }

    private func mutedGains(for mixPlan: AudioMixPlan) -> [AudioTrackKind: Double] {
        Dictionary(uniqueKeysWithValues: mixPlan.tracks.map { ($0.kind, 0) })
    }

    private func audibleSourceAudioTracks(
        in mixPlan: AudioMixPlan,
        sourceAudioTracks: [AudioTrackKind]
    ) -> [AudioTrackKind] {
        let availableTracks = Set(sourceAudioTracks)
        return mixPlan.tracks.compactMap { track in
            guard track.gain > 0, availableTracks.contains(track.kind) else {
                return nil
            }

            return track.kind
        }
    }

    private static func deduplicated(_ audioTracks: [AudioTrackKind]) -> [AudioTrackKind] {
        var seen: Set<AudioTrackKind> = []
        return audioTracks.filter { seen.insert($0).inserted }
    }
}
