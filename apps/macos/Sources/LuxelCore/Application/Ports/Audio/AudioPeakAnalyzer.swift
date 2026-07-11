import Foundation

public struct AudioPeakAnalysisRequest: Equatable, Sendable {
    public let inputFileURL: URL
    public let timeRange: TimeRange
    public let editPlan: TimelineEditPlan
    public let audioTracks: [AudioTrackKind]

    public init(
        inputFileURL: URL,
        timeRange: TimeRange,
        editPlan: TimelineEditPlan = .empty,
        audioTracks: [AudioTrackKind]
    ) {
        self.inputFileURL = inputFileURL
        self.timeRange = timeRange
        self.editPlan = editPlan
        self.audioTracks = Self.deduplicated(audioTracks)
    }

    private static func deduplicated(_ audioTracks: [AudioTrackKind]) -> [AudioTrackKind] {
        var seen: Set<AudioTrackKind> = []
        return audioTracks.filter { seen.insert($0).inserted }
    }
}

public protocol AudioPeakAnalyzer: Sendable {
    func measurePeaks(_ request: AudioPeakAnalysisRequest) async throws -> [AudioTrackKind: Double]
}
