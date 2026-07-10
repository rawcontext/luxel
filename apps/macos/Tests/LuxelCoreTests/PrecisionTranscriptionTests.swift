import Foundation
import LuxelCore
import Testing

@Suite("Precision transcription")
struct PrecisionTranscriptionTests {
    @Test("all pinned languages and regional variants resolve")
    func supportedLanguagesAndRegionalVariantsResolve() throws {
        for code in PrecisionTranscriptionLanguageCatalog.supportedCodes {
            #expect(
                try PrecisionTranscriptionLanguageCatalog.languageCode(
                    for: Locale(identifier: code)
                ).identifier.lowercased() == code
            )
        }
        #expect(
            try PrecisionTranscriptionLanguageCatalog.languageCode(
                for: Locale(identifier: "en-US")
            ).identifier == "en"
        )
        #expect(
            try PrecisionTranscriptionLanguageCatalog.languageCode(
                for: Locale(identifier: "pt-BR")
            ).identifier == "pt"
        )
        #expect(
            try PrecisionTranscriptionLanguageCatalog.languageCode(
                for: Locale(identifier: "de-DE")
            ).identifier == "de"
        )
    }

    @Test("unsupported Asian languages fail explicitly", arguments: ["ja-JP", "ko-KR", "zh-CN"])
    func unsupportedLanguagesFailExplicitly(identifier: String) {
        #expect(throws: PrecisionTranscriptionError.self) {
            try PrecisionTranscriptionLanguageCatalog.languageCode(
                for: Locale(identifier: identifier)
            )
        }
    }

    @Test("token mapper joins subwords and punctuation with weighted confidence")
    func tokenMapperJoinsSubwordsAndPunctuation() throws {
        let words = try PrecisionTokenTimingMapper.map(
            [
                PrecisionTokenTiming(token: "▁Hel", start: 0, end: 0.2, confidence: 0.8),
                PrecisionTokenTiming(token: "lo", start: 0.2, end: 0.5, confidence: 1),
                PrecisionTokenTiming(token: ",", start: 0.5, end: 0.6, confidence: 0.9),
                PrecisionTokenTiming(token: "▁world", start: 0.6, end: 1, confidence: 0.95),
                PrecisionTokenTiming(token: "!", start: 1, end: 1.1, confidence: 0.9)
            ],
            expectedText: "Hello, world!"
        )

        #expect(words.map(\.text) == ["Hello,", "world!"])
        #expect(words[0].start == 0)
        #expect(words[0].end == 0.6)
        #expect(abs(words[0].confidence - 0.916_666_666_7) < 0.000_001)
        #expect(words[1].start == 0.6)
        #expect(words[1].end == 1.1)
        _ = try words[0].timedSpan(id: "word-0", source: .system)
        _ = try words[0].captionWord()
    }

    @Test("token mapper handles blanks apostrophes hyphens diacritics Cyrillic and Greek")
    func tokenMapperHandlesRepresentativeText() throws {
        let cases: [([String], String)] = [
            (["<blank>", "▁don", "'", "t", "▁re", "-", "enter"], "don't re-enter"),
            (["▁café", "▁déjà"], "café déjà"),
            (["▁Привет", "▁мир"], "Привет мир"),
            (["▁Γειά", "▁σου"], "Γειά σου")
        ]
        for (tokens, expected) in cases {
            let timings = tokens.enumerated().map { index, token in
                PrecisionTokenTiming(
                    token: token,
                    start: Double(index) * 0.1,
                    end: Double(index + 1) * 0.1,
                    confidence: 0.9
                )
            }
            let words = try PrecisionTokenTimingMapper.map(timings, expectedText: expected)
            #expect(words.map(\.text).joined(separator: " ") == expected)
        }
    }

    @Test("token mapper rejects missing mismatched and materially overlapping timings")
    func tokenMapperRejectsInvalidTimingOutput() {
        #expect(throws: PrecisionTranscriptionError.missingTokenTimings) {
            try PrecisionTokenTimingMapper.map([], expectedText: "hello")
        }
        #expect(throws: PrecisionTranscriptionError.textReconstructionMismatch) {
            try PrecisionTokenTimingMapper.map(
                [PrecisionTokenTiming(token: "▁hello", start: 0, end: 1, confidence: 1)],
                expectedText: "goodbye"
            )
        }
        #expect(throws: PrecisionTranscriptionError.invalidTokenTimings) {
            try PrecisionTokenTimingMapper.map(
                [
                    PrecisionTokenTiming(token: "▁one", start: 0, end: 1, confidence: 1),
                    PrecisionTokenTiming(token: "▁two", start: 0.5, end: 1.5, confidence: 1)
                ],
                expectedText: "one two"
            )
        }
        #expect(throws: PrecisionTranscriptionError.invalidTokenTimings) {
            try PrecisionTokenTimingMapper.map(
                [PrecisionTokenTiming(token: "▁bad", start: .nan, end: 1, confidence: 1)],
                expectedText: "bad"
            )
        }
        for timing in [
            PrecisionTokenTiming(token: "▁bad", start: -1, end: 1, confidence: 1),
            PrecisionTokenTiming(token: "▁bad", start: 1, end: 1, confidence: 1),
            PrecisionTokenTiming(token: "▁bad", start: 0, end: .infinity, confidence: 1),
            PrecisionTokenTiming(token: "▁bad", start: 0, end: 1, confidence: .nan),
            PrecisionTokenTiming(token: "▁bad", start: 0, end: 1, confidence: 1.1)
        ] {
            #expect(throws: PrecisionTranscriptionError.invalidTokenTimings) {
                try PrecisionTokenTimingMapper.map([timing], expectedText: "bad")
            }
        }
    }

    @Test("tiny timing inversions are clamped without overlap")
    func tinyTimingInversionsAreClamped() throws {
        let words = try PrecisionTokenTimingMapper.map(
            [
                PrecisionTokenTiming(token: "▁one", start: 0, end: 1, confidence: 1),
                PrecisionTokenTiming(token: "▁two", start: 0.9995, end: 1.5, confidence: 1)
            ],
            expectedText: "one two"
        )
        #expect(words[1].start == words[0].end)
    }

    @Test("selected engine router never falls back from Precision to Apple")
    func selectedEngineRouterNeverFallsBack() async throws {
        let apple = TimedTranscriberSpy()
        let precision = TimedTranscriberSpy(error: PrecisionTranscriptionError.inferenceFailed)
        let router = SelectedEngineTimedSpeechTranscriber(
            appleSpeech: apple,
            precision: precision
        )

        await #expect(throws: PrecisionTranscriptionError.inferenceFailed) {
            try await router.transcribe(
                TimedSpeechTranscriptionRequest(
                    audioURL: URL(fileURLWithPath: "/tmp/audio.m4a"),
                    locale: Locale(identifier: "en-US"),
                    transcriptionProvenance: TranscriptionProvenance(
                        engine: .parakeetTDTv3,
                        modelRevision: "revision",
                        configurationRevision: "config"
                    )
                )
            )
        }
        #expect(await precision.callCount == 1)
        #expect(await apple.callCount == 0)
    }

    @Test("timed transcript and caption adapters share mapped words and provenance")
    func adaptersShareRecognitionResult() async throws {
        let provenance = TranscriptionProvenance(
            engine: .parakeetTDTv3,
            modelRevision: "revision",
            configurationRevision: "config"
        )
        let recognizer = PrecisionRecognizerStub(
            result: PrecisionRecognitionResult(
                text: "Hello world.",
                words: [
                    PrecisionRecognizedWord(
                        text: "Hello",
                        start: 0,
                        end: 0.4,
                        confidence: 0.9
                    ),
                    PrecisionRecognizedWord(
                        text: "world.",
                        start: 0.4,
                        end: 1,
                        confidence: 0.8
                    )
                ],
                language: Locale.LanguageCode("en"),
                confidence: 0.85,
                provenance: provenance
            )
        )
        let audioURL = URL(fileURLWithPath: "/tmp/precision-adapter.m4a")
        let spans = try await PrecisionTimedSpeechTranscriber(engine: recognizer).transcribe(
            TimedSpeechTranscriptionRequest(
                audioURL: audioURL,
                locale: Locale(identifier: "en-US"),
                source: .system,
                transcriptionProvenance: provenance
            )
        )
        let progress = PrecisionProgressCapture()
        let caption = try await PrecisionCaptionSpeechTranscriber(
            engine: recognizer
        ).transcribe(
            SpeechTranscriptionRequest(
                audioURL: audioURL,
                preferredLanguage: Locale.LanguageCode("en")
            ),
            progress: { progress.append($0.fractionCompleted) }
        )

        #expect(spans.map(\.text) == caption.words.map(\.text))
        #expect(spans.map(\.start) == caption.words.map(\.timeRange.start))
        #expect(spans.allSatisfy { $0.source == .system })
        #expect(caption.provenance == provenance)
        #expect(progress.values == [0.2, 1])
    }

    @Test("caption provenance survives Codable editing and time mapping")
    func captionProvenanceSurvivesPersistenceAndEditing() throws {
        let provenance = TranscriptionProvenance(
            engine: .parakeetTDTv3,
            modelRevision: "revision",
            configurationRevision: "config"
        )
        let track = try CaptionTrack(
            cues: [
                CaptionCue(timeRange: TimeRange(start: 1, end: 2), text: "Hello")
            ],
            language: Locale.LanguageCode("en"),
            sourceTrack: .system,
            transcriptionProvenance: provenance
        )
        let decoded = try JSONDecoder().decode(
            CaptionTrack.self,
            from: JSONEncoder().encode(track)
        )
        let edited = try CaptionTrackEditor(track: decoded).replacingCue(
            at: 0,
            with: CaptionCue(timeRange: TimeRange(start: 1, end: 2), text: "Edited")
        )
        let mapped = try CaptionExportTimeMapper(
            trimRange: TimeRange(start: 0.5, end: 2.5)
        ).map(edited)
        #expect(mapped.transcriptionProvenance == provenance)
    }

    @Test("transcript cache separates Apple and Precision provenance")
    func transcriptCacheSeparatesEngineProvenance() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "PrecisionCacheTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let audioURL = directory.appending(path: "audio.m4a")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: audioURL)
        let cache = ApplicationSupportTranscriptCache(
            cacheDirectory: directory.appending(path: "cache"))
        let transcript = try sampleTranscript(provenance: .appleSpeech)
        let appleRequest = AudioTranscriptRequest(
            audioURL: audioURL,
            transcriptionProvenance: .appleSpeech
        )
        let precisionProvenance = TranscriptionProvenance(
            engine: .parakeetTDTv3,
            modelRevision: "revision",
            configurationRevision: "config"
        )
        let precisionRequest = AudioTranscriptRequest(
            audioURL: audioURL,
            transcriptionProvenance: precisionProvenance
        )
        try cache.save(transcript, for: appleRequest)
        try cache.save(
            sampleTranscript(provenance: precisionProvenance),
            for: precisionRequest
        )

        #expect(try cache.load(for: appleRequest)?.transcriptionProvenance == .appleSpeech)
        #expect(try cache.load(for: precisionRequest)?.transcriptionProvenance == precisionProvenance)
        let files = try FileManager.default.contentsOfDirectory(
            at: directory.appending(path: "cache"),
            includingPropertiesForKeys: nil
        )
        #expect(files.count == 2)
    }

    @Test("schema 3 transcript cache documents are ignored")
    func schemaThreeCacheDocumentsAreIgnored() throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "PrecisionOldCacheTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let audioURL = directory.appending(path: "audio.m4a")
        let cacheDirectory = directory.appending(path: "cache")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("audio".utf8).write(to: audioURL)
        let cache = ApplicationSupportTranscriptCache(cacheDirectory: cacheDirectory)
        let request = AudioTranscriptRequest(audioURL: audioURL)
        try cache.save(sampleTranscript(provenance: .appleSpeech), for: request)
        let cacheFile = try #require(
            FileManager.default.contentsOfDirectory(
                at: cacheDirectory,
                includingPropertiesForKeys: nil
            ).first
        )
        var document = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: cacheFile)) as? [String: Any]
        )
        document["schemaVersion"] = 3
        try JSONSerialization.data(withJSONObject: document).write(to: cacheFile)

        #expect(try cache.load(for: request) == nil)
    }

    private func sampleTranscript(
        provenance: TranscriptionProvenance
    ) throws -> TurnSegmentedTranscript {
        let span = try TimedTranscriptSpan(id: "span-0", text: "Hello", start: 0, end: 1)
        return try TurnSegmentedTranscript(
            spans: [span],
            turns: [
                TranscriptTurn(
                    id: "turn-0",
                    spanIDs: [span.id],
                    start: 0,
                    end: 1,
                    text: "Hello"
                )
            ],
            localeIdentifier: "en-US",
            transcriptionProvenance: provenance
        )
    }
}

private actor TimedTranscriberSpy: TimedSpeechTranscriber {
    private(set) var callCount = 0
    private let error: PrecisionTranscriptionError?

    init(error: PrecisionTranscriptionError? = nil) {
        self.error = error
    }

    func transcribe(_ request: TimedSpeechTranscriptionRequest) async throws
    -> [TimedTranscriptSpan] {
        callCount += 1
        if let error { throw error }
        return [
            try TimedTranscriptSpan(id: "span", text: "Apple", start: 0, end: 1)
        ]
    }
}

private struct PrecisionRecognizerStub: PrecisionRecognizing {
    let result: PrecisionRecognitionResult

    func recognize(
        audioURL: URL,
        audioTrackIndex: Int?,
        locale: Locale,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> PrecisionRecognitionResult {
        progress(0.2)
        progress(1)
        return result
    }
}

private final class PrecisionProgressCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [Double] = []

    var values: [Double] { lock.withLock { storedValues } }
    func append(_ value: Double) { lock.withLock { storedValues.append(value) } }
}
