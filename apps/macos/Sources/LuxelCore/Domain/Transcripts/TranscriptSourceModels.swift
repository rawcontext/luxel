import Foundation

public struct TranscriptSourceContext: Codable, Equatable, Sendable {
    public static let unknown = TranscriptSourceContext(recordingAudioMode: nil)

    public let recordingAudioMode: RecordingAudioMode?

    public init(recordingAudioMode: RecordingAudioMode?) {
        self.recordingAudioMode = recordingAudioMode
    }

    public func extractionPlans(audioTrackCount: Int) -> [TranscriptExtractionPlan] {
        extractionPlans(audioTrackLayout: AudioTrackLayout(audioTrackCount: audioTrackCount))
    }

    public func extractionPlans(audioTrackLayout: AudioTrackLayout) -> [TranscriptExtractionPlan] {
        switch recordingAudioMode {
        case .some(.system):
            [TranscriptExtractionPlan(source: .system)]
        case .some(.microphone):
            [TranscriptExtractionPlan(source: .microphone)]
        case .some(.systemAndMicrophone):
            systemAndMicrophoneExtractionPlans(audioTrackLayout: audioTrackLayout)
        case .some(.none):
            [TranscriptExtractionPlan(source: nil)]
        case nil:
            markedTrackExtractionPlans(audioTrackLayout: audioTrackLayout)
                ?? [TranscriptExtractionPlan(source: nil)]
        }
    }

    public var cacheIdentifier: String {
        switch recordingAudioMode {
        case .some(.none): "none"
        case .some(.system): "system"
        case .some(.microphone): "microphone"
        case .some(.systemAndMicrophone): "systemAndMicrophone"
        case nil: "unknown"
        }
    }

    private func systemAndMicrophoneExtractionPlans(
        audioTrackLayout: AudioTrackLayout
    ) -> [TranscriptExtractionPlan] {
        guard audioTrackLayout.count > 0 else {
            return [TranscriptExtractionPlan(source: nil)]
        }
        if audioTrackLayout.count == 1 {
            guard let kind = audioTrackLayout.trackKinds[0] else {
                return [TranscriptExtractionPlan(source: nil)]
            }
            return [TranscriptExtractionPlan(source: TranscriptSourceLabel(kind))]
        }
        let systemIndex = audioTrackLayout.firstIndex(of: .system)
        let microphoneIndex = audioTrackLayout.firstIndex(of: .microphone)
        if audioTrackLayout.count == 2, systemIndex != nil || microphoneIndex != nil {
            let resolvedSystemIndex = systemIndex ?? (microphoneIndex == 0 ? 1 : 0)
            let resolvedMicrophoneIndex = microphoneIndex ?? (systemIndex == 0 ? 1 : 0)
            return [
                TranscriptExtractionPlan(source: .system, audioTrackIndex: resolvedSystemIndex),
                TranscriptExtractionPlan(source: .microphone, audioTrackIndex: resolvedMicrophoneIndex)
            ]
        }
        if let systemIndex, let microphoneIndex {
            return [
                TranscriptExtractionPlan(source: .system, audioTrackIndex: systemIndex),
                TranscriptExtractionPlan(source: .microphone, audioTrackIndex: microphoneIndex)
            ]
        }
        return [
            TranscriptExtractionPlan(source: .system, audioTrackIndex: 0),
            TranscriptExtractionPlan(source: .microphone, audioTrackIndex: 1)
        ]
    }

    private func markedTrackExtractionPlans(
        audioTrackLayout: AudioTrackLayout
    ) -> [TranscriptExtractionPlan]? {
        let plans = audioTrackLayout.trackKinds.enumerated().compactMap { index, kind in
            kind.map {
                TranscriptExtractionPlan(
                    source: TranscriptSourceLabel($0),
                    audioTrackIndex: audioTrackLayout.count > 1 ? index : nil
                )
            }
        }
        return plans.isEmpty ? nil : plans
    }
}

public struct TranscriptExtractionPlan: Equatable, Sendable {
    public let source: TranscriptSourceLabel?
    public let audioTrackIndex: Int?

    public init(source: TranscriptSourceLabel?, audioTrackIndex: Int? = nil) {
        self.source = source
        self.audioTrackIndex = audioTrackIndex
    }
}

public enum TranscriptModelError: Error, Equatable, Sendable {
    case invalidSpan
    case invalidTurn
    case invalidTranscript
    case invalidConfidence
    case invalidSpeakerLabel
    case missingSpan(String)
    case duplicateSpan(String)
    case reorderedSpan(String)
    case changedTurnText(String)
    case invalidTurnTiming(String)
    case inventedSource(String)
    case inventedSpeaker(String)
    case mixedTurnSpeakers(String)
    case unknownSpeaker(String)
    case duplicateSpeakerLabel(String)
    case unsupportedCacheSchemaVersion(Int)
}
