import Foundation

/// Diarization segments scoped to the audio they were computed from.
/// A `source` of nil means the segments apply to every span (mixed/unknown audio);
/// a concrete source restricts assignment to spans attributed to that source so
/// per-track speaker identities are never conflated.
public struct SpeakerDiarizationTrackSegments: Equatable, Sendable {
    public let source: TranscriptSourceLabel?
    public let segments: [SpeakerDiarizationSegment]

    public init(source: TranscriptSourceLabel?, segments: [SpeakerDiarizationSegment]) {
        self.source = source
        self.segments = segments
    }
}

public struct SpeakerAnnotatedSpans: Equatable, Sendable {
    public let spans: [TimedTranscriptSpan]
    public let speakers: [TranscriptSpeakerLabel]

    public init(spans: [TimedTranscriptSpan], speakers: [TranscriptSpeakerLabel]) {
        self.spans = spans
        self.speakers = speakers
    }
}

public enum SpeakerDiarizationTranscriptAnnotator {
    public static let defaultMinimumOverlapRatio = 0.5

    /// Assigns diarized speaker IDs to transcript spans by maximum time overlap.
    ///
    /// A span is labeled only when the winning speaker covers at least
    /// `minimumOverlapRatio` of the span's duration; uncertain spans stay
    /// unlabeled rather than guessing. Text, timing, confidence, and source
    /// labels are preserved untouched. Speaker labels are built in first-seen
    /// order and display as "Speaker 1", "Speaker 2", ... unless a known-speaker
    /// match supplies a name.
    public static func annotate(
        spans: [TimedTranscriptSpan],
        tracks: [SpeakerDiarizationTrackSegments],
        minimumOverlapRatio: Double = defaultMinimumOverlapRatio,
        knownSpeakerMatches: [String: KnownSpeakerMatch] = [:]
    ) throws -> SpeakerAnnotatedSpans {
        guard !tracks.isEmpty, tracks.contains(where: { !$0.segments.isEmpty }) else {
            return SpeakerAnnotatedSpans(spans: spans, speakers: [])
        }

        let annotatedSpans = try spans.map { span in
            try span.replacingSpeakerID(
                assignedSpeakerID(
                    for: span,
                    tracks: tracks,
                    minimumOverlapRatio: minimumOverlapRatio
                ))
        }

        var labels: [TranscriptSpeakerLabel] = []
        var seenSpeakerIDs: Set<String> = []
        for span in annotatedSpans {
            guard let speakerID = span.speakerID, seenSpeakerIDs.insert(speakerID).inserted else {
                continue
            }

            let match = knownSpeakerMatches[speakerID]
            labels.append(
                try TranscriptSpeakerLabel(
                    id: speakerID,
                    displayName: match?.displayName ?? LuxelLocalization.format("Speaker %d", labels.count + 1),
                    knownSpeakerID: match?.knownSpeakerID
                ))
        }

        return SpeakerAnnotatedSpans(spans: annotatedSpans, speakers: labels)
    }

    private static func assignedSpeakerID(
        for span: TimedTranscriptSpan,
        tracks: [SpeakerDiarizationTrackSegments],
        minimumOverlapRatio: Double
    ) -> String? {
        let spanDuration = span.end - span.start
        guard spanDuration > 0 else {
            return nil
        }

        var overlapBySpeaker: [String: TimeInterval] = [:]
        for track in tracks {
            guard track.source == nil || track.source == span.source else {
                continue
            }

            for segment in track.segments {
                let overlap = min(span.end, segment.end) - max(span.start, segment.start)
                guard overlap > 0 else {
                    continue
                }

                overlapBySpeaker[segment.speakerID, default: 0] += overlap
            }
        }

        let winner = overlapBySpeaker.max {
            if $0.value == $1.value {
                return $0.key > $1.key
            }

            return $0.value < $1.value
        }
        guard let winner, winner.value >= minimumOverlapRatio * spanDuration else {
            return nil
        }

        return winner.key
    }
}
