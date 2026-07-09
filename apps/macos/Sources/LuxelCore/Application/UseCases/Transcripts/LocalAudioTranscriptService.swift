import Foundation

public struct LocalAudioTranscriptService: AudioTranscriptService {
    private let transcriber: any TimedSpeechTranscriber
    private let turnSegmenter: any TranscriptTurnSegmenter
    private let rawTurnSegmenter: any TranscriptTurnSegmenter
    private let turnSegmentationMode: @Sendable () -> TranscriptTurnSegmentationMode
    private let cache: any TranscriptCache
    private let audioTrackInspector: any AudioTrackInspector

    public init(
        transcriber: any TimedSpeechTranscriber,
        turnSegmenter: any TranscriptTurnSegmenter,
        rawTurnSegmenter: any TranscriptTurnSegmenter = RawTranscriptTurnSegmenter(),
        turnSegmentationMode: @escaping @Sendable () -> TranscriptTurnSegmentationMode = {
            .semantic
        },
        cache: any TranscriptCache,
        audioTrackInspector: any AudioTrackInspector
    ) {
        self.transcriber = transcriber
        self.turnSegmenter = turnSegmenter
        self.rawTurnSegmenter = rawTurnSegmenter
        self.turnSegmentationMode = turnSegmentationMode
        self.cache = cache
        self.audioTrackInspector = audioTrackInspector
    }

    public func transcript(for request: AudioTranscriptRequest) async throws
    -> TurnSegmentedTranscript? {
        let mode = turnSegmentationMode()
        let effectiveRequest = request.replacingTurnSegmentationMode(mode)
        if let cached = try cache.load(for: effectiveRequest) {
            return cached
        }

        let audioTrackLayout = try await audioTrackInspector.audioTrackLayout(
            in: effectiveRequest.audioURL)
        let extractionPlans = effectiveRequest.sourceContext.extractionPlans(
            audioTrackLayout: audioTrackLayout)
        guard !extractionPlans.isEmpty else {
            return nil
        }

        let transcriber = transcriber
        let spans = try await withThrowingTaskGroup(
            of: (planIndex: Int, spans: [TimedTranscriptSpan]).self
        ) { group in
            for (planIndex, plan) in extractionPlans.enumerated() {
                group.addTask {
                    let extracted = try await transcriber.transcribe(
                        TimedSpeechTranscriptionRequest(
                            audioURL: effectiveRequest.audioURL,
                            locale: effectiveRequest.locale,
                            source: plan.source,
                            audioTrackIndex: plan.audioTrackIndex
                        ))
                    return (planIndex, extracted)
                }
            }

            var spansByPlanIndex = [[TimedTranscriptSpan]](
                repeating: [], count: extractionPlans.count)
            while let result = try await group.next() {
                spansByPlanIndex[result.planIndex] = result.spans
            }
            return spansByPlanIndex.flatMap { $0 }
        }

        let stableSpans = try Self.stableSortedSpans(spans)
        guard !stableSpans.isEmpty else {
            return nil
        }

        let transcript = try await segmenter(for: mode).segment(
            spans: stableSpans,
            locale: effectiveRequest.locale
        )
        try cache.save(transcript, for: effectiveRequest)
        return transcript
    }

    private func segmenter(
        for mode: TranscriptTurnSegmentationMode
    ) -> any TranscriptTurnSegmenter {
        switch mode {
        case .semantic:
            turnSegmenter
        case .raw:
            rawTurnSegmenter
        }
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

public struct RawTranscriptTurnSegmenter: TranscriptTurnSegmenter {
    private static let maximumTurnSpanCount = 80

    public init() {}

    public func segment(
        spans: [TimedTranscriptSpan],
        locale: Locale
    ) async throws -> TurnSegmentedTranscript {
        try TranscriptSegmentationValidator.makeTranscript(
            spans: spans,
            turnSpanIDs: Self.rawTurnSpanIDs(from: spans),
            localeIdentifier: locale.identifier
        )
    }

    private static func rawTurnSpanIDs(from spans: [TimedTranscriptSpan]) -> [[String]] {
        var groups: [[String]] = []
        var current: [TimedTranscriptSpan] = []

        for span in spans {
            if let last = current.last,
               current.count >= maximumTurnSpanCount || last.source != span.source {
                groups.append(current.map(\.id))
                current = []
            }

            current.append(span)
        }

        if !current.isEmpty {
            groups.append(current.map(\.id))
        }

        return groups
    }
}
