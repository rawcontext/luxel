import Foundation

public struct CaptionCue: Codable, Equatable, Sendable {
    public let timeRange: TimeRange
    public let text: String

    public init(timeRange: TimeRange, text: String) throws {
        let normalizedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else {
            throw CaptionModelError.invalidCueText
        }

        let lines = normalizedText.components(separatedBy: .newlines)
        guard lines.count <= 2, lines.allSatisfy({ !$0.isEmpty }) else {
            throw CaptionModelError.tooManyCueLines
        }

        self.timeRange = timeRange
        self.text = normalizedText
    }
}

public struct CaptionTrack: Codable, Equatable, Sendable {
    public let cues: [CaptionCue]
    public let language: Locale.LanguageCode
    public let sourceTrack: AudioTrackKind?
    public let transcriptionProvenance: TranscriptionProvenance?

    public init(
        cues: [CaptionCue],
        language: Locale.LanguageCode,
        sourceTrack: AudioTrackKind? = nil,
        transcriptionProvenance: TranscriptionProvenance? = nil
    ) throws {
        try Self.validate(cues)

        self.cues = cues
        self.language = language
        self.sourceTrack = sourceTrack
        self.transcriptionProvenance = transcriptionProvenance
    }

    private static func validate(_ cues: [CaptionCue]) throws {
        for pair in zip(cues, cues.dropFirst()) {
            if pair.1.timeRange.start < pair.0.timeRange.start {
                throw CaptionModelError.unsortedCues
            }

            if pair.1.timeRange.start < pair.0.timeRange.end {
                throw CaptionModelError.overlappingCues
            }
        }
    }
}

public struct CaptionTrackEditor: Equatable, Sendable {
    public let track: CaptionTrack

    public init(track: CaptionTrack) {
        self.track = track
    }

    public func replacingCue(at index: Int, with replacement: CaptionCue) throws -> CaptionTrack {
        _ = try cue(at: index)

        var cues = track.cues
        cues[index] = replacement
        return try makeTrack(cues: cues)
    }

    public func deletingCue(at index: Int) throws -> CaptionTrack {
        _ = try cue(at: index)

        var cues = track.cues
        cues.remove(at: index)
        return try makeTrack(cues: cues)
    }

    public func splittingCue(
        at index: Int,
        splitTime: TimeInterval,
        firstText: String,
        secondText: String
    ) throws -> CaptionTrack {
        let cue = try cue(at: index)
        guard splitTime > cue.timeRange.start, splitTime < cue.timeRange.end else {
            throw CaptionModelError.invalidCueSplitTime
        }

        var cues = track.cues
        cues.replaceSubrange(
            index...index,
            with: [
                try CaptionCue(
                    timeRange: TimeRange(start: cue.timeRange.start, end: splitTime),
                    text: firstText
                ),
                try CaptionCue(
                    timeRange: TimeRange(start: splitTime, end: cue.timeRange.end),
                    text: secondText
                )
            ])
        return try makeTrack(cues: cues)
    }

    public func mergingCue(at index: Int) throws -> CaptionTrack {
        let first = try cue(at: index)
        let second = try cue(at: index + 1)

        var cues = track.cues
        cues.replaceSubrange(
            index...(index + 1),
            with: [
                try CaptionCue(
                    timeRange: TimeRange(start: first.timeRange.start, end: second.timeRange.end),
                    text: [first.text, second.text].joined(separator: "\n")
                )
            ])
        return try makeTrack(cues: cues)
    }

    private func cue(at index: Int) throws -> CaptionCue {
        guard track.cues.indices.contains(index) else {
            throw CaptionModelError.invalidCueIndex
        }

        return track.cues[index]
    }

    private func makeTrack(cues: [CaptionCue]) throws -> CaptionTrack {
        try CaptionTrack(
            cues: cues,
            language: track.language,
            sourceTrack: track.sourceTrack,
            transcriptionProvenance: track.transcriptionProvenance
        )
    }
}

public struct CaptionSidecarDocument: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let track: CaptionTrack

    public init(
        schemaVersion: Int = CaptionSidecarDocument.currentSchemaVersion,
        track: CaptionTrack
    ) throws {
        self.schemaVersion = try validatedSidecarSchemaVersion(
            schemaVersion, current: Self.currentSchemaVersion,
            error: CaptionModelError.unsupportedSidecarSchemaVersion
        )
        self.track = track
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
            track: container.decode(CaptionTrack.self, forKey: .track)
        )
    }
}

public typealias CaptionExportTimeMapper = EditedTimelineMapper

extension EditedTimelineMapper {
    public func map(_ track: CaptionTrack) throws -> CaptionTrack {
        try CaptionTrack(
            cues: track.cues.flatMap { cue in
                try map(cue)
            },
            language: track.language,
            sourceTrack: track.sourceTrack,
            transcriptionProvenance: track.transcriptionProvenance
        )
    }

    private func map(_ cue: CaptionCue) throws -> [CaptionCue] {
        try mapSourceRange(cue.timeRange).map {
            try CaptionCue(timeRange: $0, text: cue.text)
        }
    }
}

public struct CaptionRenderOptions: Codable, Equatable, Sendable {
    public let burnIn: Bool
    public let position: CaptionPosition
    public let size: CaptionSize
    public let theme: CaptionTheme

    public init(
        burnIn: Bool = false,
        position: CaptionPosition = .lowerThird,
        size: CaptionSize = .medium,
        theme: CaptionTheme = .darkGlass
    ) {
        self.burnIn = burnIn
        self.position = position
        self.size = size
        self.theme = theme
    }
}
