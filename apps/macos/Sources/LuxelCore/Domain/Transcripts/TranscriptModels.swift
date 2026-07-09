import Foundation

public enum TranscriptSourceLabel: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case system
    case microphone

    public init(_ audioTrackKind: AudioTrackKind) {
        switch audioTrackKind {
        case .system:
            self = .system
        case .microphone:
            self = .microphone
        }
    }

    public var displayName: String {
        switch self {
        case .system:
            "System Audio"
        case .microphone:
            "Microphone"
        }
    }
}

public struct TimedTranscriptSpan: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval
    public let confidence: Double?
    public let source: TranscriptSourceLabel?

    public init(
        id: String,
        text: String,
        start: TimeInterval,
        end: TimeInterval,
        confidence: Double? = nil,
        source: TranscriptSourceLabel? = nil
    ) throws {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !normalizedText.isEmpty, start.isFinite, end.isFinite, end > start else {
            throw TranscriptModelError.invalidSpan
        }
        if let confidence, !(0...1).contains(confidence) {
            throw TranscriptModelError.invalidConfidence
        }

        self.id = id
        self.text = normalizedText
        self.start = start
        self.end = end
        self.confidence = confidence
        self.source = source
    }

    public func replacingID(_ id: String) throws -> TimedTranscriptSpan {
        try TimedTranscriptSpan(
            id: id,
            text: text,
            start: start,
            end: end,
            confidence: confidence,
            source: source
        )
    }
}

public struct TranscriptTurn: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let spanIDs: [String]
    public let start: TimeInterval
    public let end: TimeInterval
    public let text: String
    public let source: TranscriptSourceLabel?

    public init(
        id: String,
        spanIDs: [String],
        start: TimeInterval,
        end: TimeInterval,
        text: String,
        source: TranscriptSourceLabel? = nil
    ) throws {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty,
              !spanIDs.isEmpty,
              !normalizedText.isEmpty,
              start.isFinite,
              end.isFinite,
              end > start
        else {
            throw TranscriptModelError.invalidTurn
        }

        self.id = id
        self.spanIDs = spanIDs
        self.start = start
        self.end = end
        self.text = normalizedText
        self.source = source
    }
}

public struct TurnSegmentedTranscript: Codable, Equatable, Sendable {
    public let spans: [TimedTranscriptSpan]
    public let turns: [TranscriptTurn]
    public let localeIdentifier: String

    public init(
        spans: [TimedTranscriptSpan],
        turns: [TranscriptTurn],
        localeIdentifier: String
    ) throws {
        guard !spans.isEmpty, !turns.isEmpty, !localeIdentifier.isEmpty else {
            throw TranscriptModelError.invalidTranscript
        }

        self.spans = spans
        self.turns = turns
        self.localeIdentifier = localeIdentifier
        try TranscriptSegmentationValidator.validate(transcript: self)
    }

    public func span(for id: String) -> TimedTranscriptSpan? {
        spans.first { $0.id == id }
    }

    public func spans(for turn: TranscriptTurn) -> [TimedTranscriptSpan] {
        let spansByID = Dictionary(uniqueKeysWithValues: spans.map { ($0.id, $0) })
        return turn.spanIDs.compactMap { spansByID[$0] }
    }
}

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
        case .some(.none):
            "none"
        case .some(.system):
            "system"
        case .some(.microphone):
            "microphone"
        case .some(.systemAndMicrophone):
            "systemAndMicrophone"
        case nil:
            "unknown"
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

        if audioTrackLayout.count == 2,
           systemIndex != nil || microphoneIndex != nil {
            let resolvedSystemIndex = systemIndex ?? (microphoneIndex == 0 ? 1 : 0)
            let resolvedMicrophoneIndex = microphoneIndex ?? (systemIndex == 0 ? 1 : 0)

            return [
                TranscriptExtractionPlan(source: .system, audioTrackIndex: resolvedSystemIndex),
                TranscriptExtractionPlan(
                    source: .microphone,
                    audioTrackIndex: resolvedMicrophoneIndex
                )
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
    case missingSpan(String)
    case duplicateSpan(String)
    case reorderedSpan(String)
    case changedTurnText(String)
    case invalidTurnTiming(String)
    case inventedSource(String)
    case unsupportedCacheSchemaVersion(Int)
}
