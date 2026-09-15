import Foundation

private final class TranscriptExtractionProgressRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var fractions: [Double]
    private let progress: SpeechTranscriptionProgressHandler

    init(planCount: Int, progress: @escaping SpeechTranscriptionProgressHandler) {
        fractions = Array(repeating: 0, count: planCount)
        self.progress = progress
    }

    func update(planIndex: Int, fraction: Double) {
        let aggregate = lock.withLock { () -> Double? in
            let clamped = min(max(fraction, 0), 1)
            guard fractions.indices.contains(planIndex), clamped >= fractions[planIndex] else {
                return nil
            }
            fractions[planIndex] = clamped
            return fractions.reduce(0, +) / Double(fractions.count)
        }

        if let aggregate {
            progress(SpeechTranscriptionProgress(fractionCompleted: aggregate * 0.9))
        }
    }
}

public struct LocalAudioTranscriptService: AudioTranscriptService {
    private let transcriber: any TimedSpeechTranscriber
    // Several stored properties are internal (not private) because the diarization
    // members in LocalAudioTranscriptService+Diarization.swift need cross-file access.
    let turnSegmenter: any TranscriptTurnSegmenter
    private let rawTurnSegmenter: any TranscriptTurnSegmenter
    private let turnSegmentationMode: @Sendable () -> TranscriptTurnSegmentationMode
    private let speakerDiarizationMode: @Sendable () -> TranscriptSpeakerDiarizationMode
    private let transcriptLocaleOverride: @Sendable () -> Locale?
    private let transcriptionProvenance: @Sendable () async throws -> TranscriptionProvenance
    let cache: any TranscriptCache
    private let audioTrackInspector: any AudioTrackInspector
    private let speakerDiarizer: (any SpeakerDiarizer)?
    private let speakerModelStore: (any SpeakerDiarizationModelStore)?
    let knownSpeakerStore: (any KnownSpeakerProfileStore)?
    let diarizationArtifactsStore: (any SpeakerDiarizationArtifactsStore)?
    let knownSpeakerMatcherConfiguration: KnownSpeakerMatcherConfiguration

    public init(
        transcriber: any TimedSpeechTranscriber,
        turnSegmenter: any TranscriptTurnSegmenter,
        rawTurnSegmenter: any TranscriptTurnSegmenter = RawTranscriptTurnSegmenter(),
        turnSegmentationMode: @escaping @Sendable () -> TranscriptTurnSegmentationMode = {
            .semantic
        },
        speakerDiarizationMode: @escaping @Sendable () -> TranscriptSpeakerDiarizationMode = {
            .disabled
        },
        transcriptLocaleOverride: @escaping @Sendable () -> Locale? = { nil },
        transcriptionProvenance: @escaping @Sendable () async throws -> TranscriptionProvenance = {
            .appleSpeech
        },
        cache: any TranscriptCache,
        audioTrackInspector: any AudioTrackInspector,
        speakerDiarizer: (any SpeakerDiarizer)? = nil,
        speakerModelStore: (any SpeakerDiarizationModelStore)? = nil,
        knownSpeakerStore: (any KnownSpeakerProfileStore)? = nil,
        diarizationArtifactsStore: (any SpeakerDiarizationArtifactsStore)? = nil,
        knownSpeakerMatcherConfiguration: KnownSpeakerMatcherConfiguration = .default
    ) {
        self.transcriber = transcriber
        self.turnSegmenter = turnSegmenter
        self.rawTurnSegmenter = rawTurnSegmenter
        self.turnSegmentationMode = turnSegmentationMode
        self.speakerDiarizationMode = speakerDiarizationMode
        self.transcriptLocaleOverride = transcriptLocaleOverride
        self.transcriptionProvenance = transcriptionProvenance
        self.cache = cache
        self.audioTrackInspector = audioTrackInspector
        self.speakerDiarizer = speakerDiarizer
        self.speakerModelStore = speakerModelStore
        self.knownSpeakerStore = knownSpeakerStore
        self.diarizationArtifactsStore = diarizationArtifactsStore
        self.knownSpeakerMatcherConfiguration = knownSpeakerMatcherConfiguration
    }

    public func transcript(for request: AudioTranscriptRequest) async throws
        -> TurnSegmentedTranscript? {
        try await transcript(for: request, progress: { _ in })
    }

    public func transcript(
        for request: AudioTranscriptRequest,
        progress: @escaping SpeechTranscriptionProgressHandler
    ) async throws -> TurnSegmentedTranscript? {
        var effectiveRequest = try await effectiveRequest(for: request)
        if let cached = try cache.load(for: effectiveRequest) {
            return completedTranscript(cached, progress: progress)
        }

        let lease = try TranscriptionSourceLease(
            sourceURL: RecordingDocumentStore.currentMediaURL(for: effectiveRequest.audioURL),
            temporaryDirectory: FileManager.default.temporaryDirectory)
        defer { lease.release() }
        let audioTrackLayout = try await audioTrackInspector.audioTrackLayout(in: lease.url)
        let extractionPlans = effectiveRequest.sourceContext.extractionPlans(
            audioTrackLayout: audioTrackLayout)
        guard !extractionPlans.isEmpty else {
            return completedTranscript(nil, progress: progress)
        }

        let spans = try await extractSpans(
            request: effectiveRequest.replacingAudioURL(lease.url),
            extractionPlans: extractionPlans,
            progress: progress
        )
        effectiveRequest = effectiveRequest.replacingAudioURL(
            RecordingDocumentStore.currentMediaURL(for: effectiveRequest.audioURL))
        progress(SpeechTranscriptionProgress(fractionCompleted: 0.92))
        let stableSpans = try Self.stableSortedSpans(spans)
        guard !stableSpans.isEmpty else {
            return completedTranscript(nil, progress: progress)
        }

        guard effectiveRequest.speakerDiarizationMode == .enabled,
            let speakerDiarizer,
            let speakerModelStore
        else {
            let transcript = try await segmentedTranscript(
                spans: stableSpans, mode: effectiveRequest.turnSegmentationMode, locale: effectiveRequest.locale
            ).replacingTranscriptionProvenance(effectiveRequest.transcriptionProvenance)
            try cache.save(transcript, for: effectiveRequest)
            return completedTranscript(transcript, progress: progress)
        }

        progress(SpeechTranscriptionProgress(fractionCompleted: 0.95))
        let diarized = try await diarizedOrFallbackTranscript(
            spans: stableSpans,
            extractionPlans: extractionPlans,
            request: effectiveRequest,
            diarizer: speakerDiarizer,
            modelStore: speakerModelStore
        )
        let transcript = try diarized.replacingTranscriptionProvenance(
            effectiveRequest.transcriptionProvenance
        )
        return completedTranscript(transcript, progress: progress)
    }

    public func storeUpdatedTranscript(
        _ transcript: TurnSegmentedTranscript,
        for request: AudioTranscriptRequest
    ) async throws {
        try cache.save(transcript, for: try await effectiveRequest(for: request))
    }

    private func completedTranscript(
        _ transcript: TurnSegmentedTranscript?,
        progress: SpeechTranscriptionProgressHandler
    ) -> TurnSegmentedTranscript? {
        progress(SpeechTranscriptionProgress(fractionCompleted: 1))
        return transcript
    }

    private func extractSpans(
        request: AudioTranscriptRequest,
        extractionPlans: [TranscriptExtractionPlan],
        progress: @escaping SpeechTranscriptionProgressHandler
    ) async throws -> [TimedTranscriptSpan] {
        let transcriber = transcriber
        let progressRelay = TranscriptExtractionProgressRelay(
            planCount: extractionPlans.count,
            progress: progress
        )
        return try await withThrowingTaskGroup(
            of: (planIndex: Int, spans: [TimedTranscriptSpan]).self
        ) { group in
            for (planIndex, plan) in extractionPlans.enumerated() {
                group.addTask {
                    let extracted = try await transcriber.transcribe(
                        TimedSpeechTranscriptionRequest(
                            audioURL: request.audioURL,
                            locale: request.locale,
                            source: plan.source,
                            audioTrackIndex: plan.audioTrackIndex,
                            transcriptionProvenance: request.transcriptionProvenance
                        ),
                        progress: {
                            progressRelay.update(
                                planIndex: planIndex,
                                fraction: $0.fractionCompleted
                            )
                        }
                    )
                    progressRelay.update(planIndex: planIndex, fraction: 1)
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
    }

    private func effectiveRequest(for request: AudioTranscriptRequest) async throws
        -> AudioTranscriptRequest {
        var effective = request.replacingTurnSegmentationMode(turnSegmentationMode())
        if let locale = transcriptLocaleOverride() {
            effective = effective.replacingLocale(locale)
        }
        effective = effective.replacingTranscriptionProvenance(
            try await transcriptionProvenance()
        )

        let diarizationRequested =
            speakerDiarizationMode() == .enabled
            && speakerDiarizer != nil
            && speakerModelStore != nil
        guard diarizationRequested, let speakerModelStore else {
            return effective.replacingSpeakerDiarizationMode(.disabled)
        }

        let modelRevision = await speakerModelStore.modelInfo().revision
        let libraryRevision = (try? knownSpeakerStore?.library())?.revision
        return effective.replacingSpeakerDiarizationMode(
            .enabled,
            modelRevision: modelRevision,
            libraryRevision: libraryRevision
        )
    }

    func segmentedTranscript(
        spans: [TimedTranscriptSpan],
        mode: TranscriptTurnSegmentationMode,
        locale: Locale
    ) async throws -> TurnSegmentedTranscript {
        try await segmenter(for: mode).segment(spans: spans, locale: locale)
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
        let reconciledSpans = CrossSourceEchoTranscriptFilter.removingEcho(from: sortedSpans)

        return try reconciledSpans.enumerated().map { index, span in
            try span.replacingID("span-\(index)")
        }
    }
}
