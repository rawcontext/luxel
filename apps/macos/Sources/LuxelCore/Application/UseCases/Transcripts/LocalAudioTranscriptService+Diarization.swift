import Foundation

extension LocalAudioTranscriptService {
    private struct DiarizationCollection {
        var tracks: [SpeakerDiarizationTrackSegments] = []
        var artifactTracks: [SpeakerDiarizationArtifacts.Track] = []
        var speakerEmbeddings: [String: [Float]] = [:]
    }

    func diarizedOrFallbackTranscript(
        spans: [TimedTranscriptSpan],
        extractionPlans: [TranscriptExtractionPlan],
        request: AudioTranscriptRequest,
        diarizer: any SpeakerDiarizer,
        modelStore: any SpeakerDiarizationModelStore
    ) async throws -> TurnSegmentedTranscript {
        do {
            let transcript = try await diarizedTranscript(
                spans: spans,
                extractionPlans: extractionPlans,
                request: request,
                diarizer: diarizer,
                modelStore: modelStore
            )
            let identified = try transcript.replacingTranscriptionProvenance(
                request.transcriptionProvenance
            )
            try cache.save(identified, for: request)
            return identified
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Diarization must never discard a valid transcript: fall back to the
            // non-diarized result and save it only under the non-diarized key.
            let transcript = try await segmentedTranscript(
                spans: spans,
                mode: request.turnSegmentationMode,
                locale: request.locale
            )
            let identified = try transcript.replacingTranscriptionProvenance(
                request.transcriptionProvenance
            )
            try cache.save(
                identified,
                for: request.replacingSpeakerDiarizationMode(.disabled)
            )
            return identified
        }
    }

    private func diarizedTranscript(
        spans: [TimedTranscriptSpan],
        extractionPlans: [TranscriptExtractionPlan],
        request: AudioTranscriptRequest,
        diarizer: any SpeakerDiarizer,
        modelStore: any SpeakerDiarizationModelStore
    ) async throws -> TurnSegmentedTranscript {
        let modelState = await modelStore.currentState()
        if !modelState.isReady {
            _ = try await modelStore.prepareModel()
        }

        let collection = try await collectDiarization(
            extractionPlans: extractionPlans,
            request: request,
            diarizer: diarizer
        )
        let library = (try? knownSpeakerStore?.library()) ?? .empty
        let matches = knownSpeakerMatches(
            for: collection.speakerEmbeddings,
            library: library,
            modelRevision: request.speakerModelRevision
        )
        let annotated = try SpeakerDiarizationTranscriptAnnotator.annotate(
            spans: spans,
            tracks: collection.tracks,
            knownSpeakerMatches: matches
        )

        let transcript: TurnSegmentedTranscript
        if annotated.speakers.isEmpty {
            transcript = try await segmentedTranscript(
                spans: spans,
                mode: request.turnSegmentationMode,
                locale: request.locale
            )
        } else {
            transcript = try await speakerAwareSegmentedTranscript(
                annotated: annotated,
                plainSpans: spans,
                mode: request.turnSegmentationMode,
                locale: request.locale
            )
        }

        try? diarizationArtifactsStore?.save(
            SpeakerDiarizationArtifacts(
                modelRevision: request.speakerModelRevision,
                tracks: collection.artifactTracks,
                speakerEmbeddings: collection.speakerEmbeddings
            ),
            audioURL: request.audioURL
        )
        recordKnownSpeakerMatches(matches, library: library)
        return transcript
    }

    private func collectDiarization(
        extractionPlans: [TranscriptExtractionPlan],
        request: AudioTranscriptRequest,
        diarizer: any SpeakerDiarizer
    ) async throws -> DiarizationCollection {
        let namespaceBySource = extractionPlans.count > 1
        var collection = DiarizationCollection()
        for plan in extractionPlans {
            let output = try await diarizer.diarize(
                SpeakerDiarizationRequest(
                    audioURL: request.audioURL,
                    audioTrackIndex: plan.audioTrackIndex,
                    modelRevision: request.speakerModelRevision,
                    speakerCountHint: request.speakerCountHint
                ))
            let namespace = namespaceBySource ? plan.source?.rawValue : nil
            let segments = output.segments.map {
                SpeakerDiarizationSegment(
                    speakerID: Self.namespacedSpeakerID($0.speakerID, namespace: namespace),
                    start: $0.start,
                    end: $0.end
                )
            }
            collection.tracks.append(
                SpeakerDiarizationTrackSegments(source: plan.source, segments: segments))
            collection.artifactTracks.append(
                SpeakerDiarizationArtifacts.Track(
                    source: plan.source,
                    audioTrackIndex: plan.audioTrackIndex,
                    segments: segments
                ))
            for (speakerID, embedding) in output.speakerEmbeddings {
                collection.speakerEmbeddings[
                    Self.namespacedSpeakerID(speakerID, namespace: namespace)
                ] = embedding
            }
        }

        return collection
    }

    private func knownSpeakerMatches(
        for speakerEmbeddings: [String: [Float]],
        library: KnownSpeakerLibrary,
        modelRevision: String?
    ) -> [String: KnownSpeakerMatch] {
        guard !library.profiles.isEmpty, !speakerEmbeddings.isEmpty, let modelRevision else {
            return [:]
        }

        // Known-speaker matching must never fail diarization; anonymous labels
        // are always an acceptable outcome.
        let matcher = KnownSpeakerMatcher(
            configuration: knownSpeakerMatcherConfiguration,
            modelIdentifier: modelRevision
        )
        return matcher.matches(for: speakerEmbeddings, library: library)
    }

    private func speakerAwareSegmentedTranscript(
        annotated: SpeakerAnnotatedSpans,
        plainSpans: [TimedTranscriptSpan],
        mode: TranscriptTurnSegmentationMode,
        locale: Locale
    ) async throws -> TurnSegmentedTranscript {
        let turnSpanIDs: [[String]]
        switch mode {
        case .raw:
            turnSpanIDs = RawTranscriptTurnSegmenter.turnSpanIDs(from: annotated.spans)
        case .semantic:
            // The language model segments plain spans so it can never invent or
            // rename speakers; deterministic speaker boundaries are applied after.
            let semanticTranscript = try await turnSegmenter.segment(
                spans: plainSpans,
                locale: locale
            )
            turnSpanIDs = Self.splittingTurnsOnSpeakerChanges(
                turnSpanIDs: semanticTranscript.turns.map(\.spanIDs),
                spans: annotated.spans
            )
        }

        return try TranscriptSegmentationValidator.makeTranscript(
            spans: annotated.spans,
            turnSpanIDs: turnSpanIDs,
            localeIdentifier: locale.identifier,
            speakers: annotated.speakers
        )
    }

    private func recordKnownSpeakerMatches(
        _ matches: [String: KnownSpeakerMatch],
        library: KnownSpeakerLibrary
    ) {
        guard let knownSpeakerStore, !matches.isEmpty else {
            return
        }

        for profileID in Set(matches.values.map(\.knownSpeakerID)) {
            guard var profile = library.profiles.first(where: { $0.id == profileID }) else {
                continue
            }

            profile.matchedRecordingCount += 1
            profile.lastMatchedAt = Date()
            profile.updatedAt = Date()
            _ = try? knownSpeakerStore.save(profile)
        }
    }

    static func splittingTurnsOnSpeakerChanges(
        turnSpanIDs: [[String]],
        spans: [TimedTranscriptSpan]
    ) -> [[String]] {
        let speakerBySpanID = Dictionary(
            uniqueKeysWithValues: spans.map { ($0.id, $0.speakerID) })

        return turnSpanIDs.flatMap { spanIDs -> [[String]] in
            var groups: [[String]] = []
            var current: [String] = []
            var currentSpeaker: String??

            for spanID in spanIDs {
                let speaker = speakerBySpanID[spanID] ?? nil
                if let existing = currentSpeaker, existing != speaker {
                    groups.append(current)
                    current = []
                }

                current.append(spanID)
                currentSpeaker = speaker
            }

            if !current.isEmpty {
                groups.append(current)
            }

            return groups
        }
    }

    static func namespacedSpeakerID(_ speakerID: String, namespace: String?) -> String {
        guard let namespace else {
            return speakerID
        }

        return "\(namespace):\(speakerID)"
    }
}
