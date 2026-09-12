import Foundation

public enum TranscriptEngine: String, Codable, Equatable, Sendable {
    case appleSpeech
    case parakeetTDTv3
}

public struct TranscriptionProvenance: Codable, Equatable, Sendable {
    public let engine: TranscriptEngine
    public let modelRevision: String?
    public let configurationRevision: String?

    public init(
        engine: TranscriptEngine,
        modelRevision: String? = nil,
        configurationRevision: String? = nil
    ) {
        self.engine = engine
        self.modelRevision = modelRevision
        self.configurationRevision = configurationRevision
    }

    public static let appleSpeech = TranscriptionProvenance(
        engine: .appleSpeech,
        configurationRevision: "apple-speech-adapter-v2"
    )
}

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
            LuxelLocalization.string("System Audio")
        case .microphone:
            LuxelLocalization.string("Microphone")
        }
    }
}

public struct TranscriptSpeakerLabel: Codable, Equatable, Hashable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let knownSpeakerID: UUID?

    public init(id: String, displayName: String, knownSpeakerID: UUID? = nil) throws {
        let normalizedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty, !normalizedDisplayName.isEmpty else {
            throw TranscriptModelError.invalidSpeakerLabel
        }

        self.id = id
        self.displayName = normalizedDisplayName
        self.knownSpeakerID = knownSpeakerID
    }
}

public struct TimedTranscriptSpan: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval
    public let confidence: Double?
    public let source: TranscriptSourceLabel?
    public let speakerID: String?

    public init(
        id: String,
        text: String,
        start: TimeInterval,
        end: TimeInterval,
        confidence: Double? = nil,
        source: TranscriptSourceLabel? = nil,
        speakerID: String? = nil
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
        self.speakerID = speakerID.flatMap { $0.isEmpty ? nil : $0 }
    }

    public func replacingID(_ id: String) throws -> TimedTranscriptSpan {
        try TimedTranscriptSpan(
            id: id,
            text: text,
            start: start,
            end: end,
            confidence: confidence,
            source: source,
            speakerID: speakerID
        )
    }

    public func replacingSpeakerID(_ speakerID: String?) throws -> TimedTranscriptSpan {
        try TimedTranscriptSpan(
            id: id,
            text: text,
            start: start,
            end: end,
            confidence: confidence,
            source: source,
            speakerID: speakerID
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
    public let speakerID: String?

    public init(
        id: String,
        spanIDs: [String],
        start: TimeInterval,
        end: TimeInterval,
        text: String,
        source: TranscriptSourceLabel? = nil,
        speakerID: String? = nil
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
        self.speakerID = speakerID.flatMap { $0.isEmpty ? nil : $0 }
    }

    public func replacingSpeakerID(_ speakerID: String?) throws -> TranscriptTurn {
        try TranscriptTurn(
            id: id,
            spanIDs: spanIDs,
            start: start,
            end: end,
            text: text,
            source: source,
            speakerID: speakerID
        )
    }
}

public struct TurnSegmentedTranscript: Codable, Equatable, Sendable {
    public let spans: [TimedTranscriptSpan]
    public let turns: [TranscriptTurn]
    public let localeIdentifier: String
    public let speakers: [TranscriptSpeakerLabel]
    public let transcriptionProvenance: TranscriptionProvenance?

    public init(
        spans: [TimedTranscriptSpan],
        turns: [TranscriptTurn],
        localeIdentifier: String,
        speakers: [TranscriptSpeakerLabel] = [],
        transcriptionProvenance: TranscriptionProvenance? = nil
    ) throws {
        guard !spans.isEmpty, !turns.isEmpty, !localeIdentifier.isEmpty else {
            throw TranscriptModelError.invalidTranscript
        }

        self.spans = spans
        self.turns = turns
        self.localeIdentifier = localeIdentifier
        self.speakers = speakers
        self.transcriptionProvenance = transcriptionProvenance
        try TranscriptSegmentationValidator.validate(transcript: self)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        spans = try container.decode([TimedTranscriptSpan].self, forKey: .spans)
        turns = try container.decode([TranscriptTurn].self, forKey: .turns)
        localeIdentifier = try container.decode(String.self, forKey: .localeIdentifier)
        speakers =
            try container.decodeIfPresent([TranscriptSpeakerLabel].self, forKey: .speakers) ?? []
        transcriptionProvenance = try container.decodeIfPresent(
            TranscriptionProvenance.self,
            forKey: .transcriptionProvenance
        )
    }

    public func span(for id: String) -> TimedTranscriptSpan? {
        spans.first { $0.id == id }
    }

    public func spans(for turn: TranscriptTurn) -> [TimedTranscriptSpan] {
        let spansByID = Dictionary(uniqueKeysWithValues: spans.map { ($0.id, $0) })
        return turn.spanIDs.compactMap { spansByID[$0] }
    }

    public func speaker(for id: String?) -> TranscriptSpeakerLabel? {
        guard let id else {
            return nil
        }

        return speakers.first { $0.id == id }
    }

    public func replacingSpeakerLabel(_ label: TranscriptSpeakerLabel) throws
        -> TurnSegmentedTranscript {
        guard speakers.contains(where: { $0.id == label.id }) else {
            throw TranscriptModelError.unknownSpeaker(label.id)
        }

        return try TurnSegmentedTranscript(
            spans: spans,
            turns: turns,
            localeIdentifier: localeIdentifier,
            speakers: speakers.map { $0.id == label.id ? label : $0 },
            transcriptionProvenance: transcriptionProvenance
        )
    }

    public func mergingSpeaker(
        id speakerID: String,
        into targetSpeakerID: String
    ) throws -> TurnSegmentedTranscript {
        guard speakers.contains(where: { $0.id == speakerID }) else {
            throw TranscriptModelError.unknownSpeaker(speakerID)
        }
        guard speakers.contains(where: { $0.id == targetSpeakerID }) else {
            throw TranscriptModelError.unknownSpeaker(targetSpeakerID)
        }
        guard speakerID != targetSpeakerID else {
            return self
        }

        return try TurnSegmentedTranscript(
            spans: try spans.map {
                try $0.replacingSpeakerID(
                    $0.speakerID == speakerID ? targetSpeakerID : $0.speakerID)
            },
            turns: try turns.map {
                try $0.replacingSpeakerID(
                    $0.speakerID == speakerID ? targetSpeakerID : $0.speakerID)
            },
            localeIdentifier: localeIdentifier,
            speakers: speakers.filter { $0.id != speakerID },
            transcriptionProvenance: transcriptionProvenance
        )
    }

    public func replacingTranscriptionProvenance(
        _ provenance: TranscriptionProvenance?
    ) throws -> TurnSegmentedTranscript {
        try TurnSegmentedTranscript(
            spans: spans,
            turns: turns,
            localeIdentifier: localeIdentifier,
            speakers: speakers,
            transcriptionProvenance: provenance
        )
    }
}
