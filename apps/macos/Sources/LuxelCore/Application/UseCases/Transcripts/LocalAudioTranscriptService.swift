import Foundation

public struct LocalAudioTranscriptService: AudioTranscriptService {
    private let transcriber: any TimedSpeechTranscriber
    private let turnSegmenter: any TranscriptTurnSegmenter
    private let cache: any TranscriptCache
    private let audioTrackInspector: any AudioTrackInspector

    public init(
        transcriber: any TimedSpeechTranscriber,
        turnSegmenter: any TranscriptTurnSegmenter,
        cache: any TranscriptCache,
        audioTrackInspector: any AudioTrackInspector
    ) {
        self.transcriber = transcriber
        self.turnSegmenter = turnSegmenter
        self.cache = cache
        self.audioTrackInspector = audioTrackInspector
    }

    public func transcript(for request: AudioTranscriptRequest) async throws
    -> TurnSegmentedTranscript? {
        if let cached = try cache.load(for: request) {
            return cached
        }

        let audioTrackCount = try await audioTrackInspector.audioTrackCount(in: request.audioURL)
        let extractionPlans = request.sourceContext.extractionPlans(audioTrackCount: audioTrackCount)
        guard !extractionPlans.isEmpty else {
            return nil
        }

        var spans: [TimedTranscriptSpan] = []
        for plan in extractionPlans {
            let extracted = try await transcriber.transcribe(
                TimedSpeechTranscriptionRequest(
                    audioURL: request.audioURL,
                    locale: request.locale,
                    source: plan.source,
                    audioTrackIndex: plan.audioTrackIndex
                ))
            spans.append(contentsOf: extracted)
        }

        let stableSpans = try Self.stableSortedSpans(spans)
        guard !stableSpans.isEmpty else {
            return nil
        }

        let transcript = try await turnSegmenter.segment(
            spans: stableSpans,
            locale: request.locale
        )
        try cache.save(transcript, for: request)
        return transcript
    }

    private static func stableSortedSpans(_ spans: [TimedTranscriptSpan]) throws
    -> [TimedTranscriptSpan] {
        let sortedSpans = spans.sorted {
            if $0.start == $1.start {
                if $0.end == $1.end {
                    return ($0.source?.rawValue ?? "") < ($1.source?.rawValue ?? "")
                }

                return $0.end < $1.end
            }

            return $0.start < $1.start
        }

        return try sortedSpans.enumerated().map { index, span in
            try span.replacingID("span-\(index)")
        }
    }
}
