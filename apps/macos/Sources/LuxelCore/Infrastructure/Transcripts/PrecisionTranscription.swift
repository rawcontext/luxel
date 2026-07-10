import FluidAudio
import Foundation

public enum PrecisionTranscriptionError: Error, Equatable, Sendable {
    case modelNotInstalled
    case modelCorrupt
    case unsupportedLanguage(String)
    case unsupportedHardware
    case missingTokenTimings
    case invalidTokenTimings
    case textReconstructionMismatch
    case inferenceFailed
    case appleCaptionTranscriberUnavailable
}

extension PrecisionTranscriptionError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .modelNotInstalled:
            "Precision Transcription is not installed. Open Settings to download it or switch to Apple Speech."
        case .modelCorrupt:
            "The Precision Transcription model needs repair. Re-download it in Settings or switch to Apple Speech."
        case .unsupportedLanguage(let code):
            "Precision Transcription does not support \(code). Choose a supported language or switch to Apple Speech."
        case .unsupportedHardware:
            "Precision Transcription requires Apple silicon. Switch to Apple Speech on this Mac."
        case .missingTokenTimings, .invalidTokenTimings, .textReconstructionMismatch:
            "Precision Transcription returned invalid word timings. Retry or switch to Apple Speech."
        case .inferenceFailed:
            "Precision Transcription failed. Retry or switch to Apple Speech."
        case .appleCaptionTranscriberUnavailable:
            "Caption transcription is not available with Apple Speech in this version of Luxel."
        }
    }
}

public enum PrecisionTranscriptionLanguageCatalog {
    public static let supportedCodes: Set<String> = [
        "bg", "cs", "da", "de", "el", "en", "es", "et", "fi", "fr", "hr", "hu",
        "it", "lt", "lv", "mt", "nl", "pl", "pt", "ro", "ru", "sk", "sl", "sv", "uk"
    ]

    public static func languageCode(for locale: Locale) throws -> Locale.LanguageCode {
        guard let languageCode = locale.language.languageCode,
              supportedCodes.contains(languageCode.identifier.lowercased())
        else {
            let requested = locale.language.languageCode?.identifier ?? locale.identifier
            throw PrecisionTranscriptionError.unsupportedLanguage(requested)
        }
        return languageCode
    }

    static func fluidLanguage(for locale: Locale) throws -> Language {
        let languageCode = try languageCode(for: locale)
        guard let language = Language(rawValue: languageCode.identifier.lowercased()) else {
            throw PrecisionTranscriptionError.unsupportedLanguage(languageCode.identifier)
        }
        return language
    }
}

public struct PrecisionTokenTiming: Equatable, Sendable {
    public let token: String
    public let start: TimeInterval
    public let end: TimeInterval
    public let confidence: Double

    public init(token: String, start: TimeInterval, end: TimeInterval, confidence: Double) {
        self.token = token
        self.start = start
        self.end = end
        self.confidence = confidence
    }
}

public struct PrecisionRecognizedWord: Equatable, Sendable {
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval
    public let confidence: Double

    public init(text: String, start: TimeInterval, end: TimeInterval, confidence: Double) {
        self.text = text
        self.start = start
        self.end = end
        self.confidence = confidence
    }

    public func timedSpan(id: String, source: TranscriptSourceLabel?) throws -> TimedTranscriptSpan {
        try TimedTranscriptSpan(
            id: id,
            text: text,
            start: start,
            end: end,
            confidence: confidence,
            source: source
        )
    }

    public func captionWord() throws -> RecognizedWord {
        try RecognizedWord(
            start: start,
            duration: end - start,
            text: text,
            confidence: confidence
        )
    }
}

public enum PrecisionTokenTimingMapper {
    private static let boundary = "▁"
    private static let epsilon: TimeInterval = 0.001
    private static let ignoredTokens: Set<String> = ["", "<blank>", "<pad>"]

    public static func map(
        _ timings: [PrecisionTokenTiming],
        expectedText: String
    ) throws -> [PrecisionRecognizedWord] {
        let content = timings.filter { !ignoredTokens.contains($0.token) }
        guard !content.isEmpty else {
            throw PrecisionTranscriptionError.missingTokenTimings
        }

        var validated: [PrecisionTokenTiming] = []
        var previousEnd: TimeInterval?
        for timing in content {
            guard timing.start.isFinite,
                  timing.end.isFinite,
                  timing.confidence.isFinite,
                  timing.start >= 0,
                  timing.end > timing.start,
                  (0...1).contains(timing.confidence)
            else {
                throw PrecisionTranscriptionError.invalidTokenTimings
            }

            var start = timing.start
            if let previousEnd, start < previousEnd {
                guard previousEnd - start <= epsilon, timing.end > previousEnd else {
                    throw PrecisionTranscriptionError.invalidTokenTimings
                }
                start = previousEnd
            }
            let adjusted = PrecisionTokenTiming(
                token: timing.token,
                start: start,
                end: timing.end,
                confidence: timing.confidence
            )
            validated.append(adjusted)
            previousEnd = adjusted.end
        }

        let decoded = validated.map(\.token).joined()
            .replacingOccurrences(of: boundary, with: " ")
        guard normalize(decoded) == normalize(expectedText) else {
            throw PrecisionTranscriptionError.textReconstructionMismatch
        }

        var groups: [[PrecisionTokenTiming]] = []
        for timing in validated {
            let startsWord =
                timing.token.hasPrefix(boundary)
                || timing.token.first?.isWhitespace == true
            if startsWord || groups.isEmpty {
                groups.append([timing])
            } else {
                groups[groups.count - 1].append(timing)
            }
        }

        let words = try groups.map { group -> PrecisionRecognizedWord in
            let text = group.map(\.token).joined()
                .replacingOccurrences(of: boundary, with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, let first = group.first, let last = group.last else {
                throw PrecisionTranscriptionError.invalidTokenTimings
            }
            let totalDuration = group.reduce(0) { $0 + ($1.end - $1.start) }
            guard totalDuration > 0 else {
                throw PrecisionTranscriptionError.invalidTokenTimings
            }
            let confidence =
                group.reduce(0) {
                    $0 + $1.confidence * ($1.end - $1.start)
                } / totalDuration
            return PrecisionRecognizedWord(
                text: text,
                start: first.start,
                end: last.end,
                confidence: confidence
            )
        }

        for pair in zip(words, words.dropFirst()) where pair.1.start < pair.0.end {
            throw PrecisionTranscriptionError.invalidTokenTimings
        }
        guard normalize(words.map(\.text).joined(separator: " ")) == normalize(expectedText) else {
            throw PrecisionTranscriptionError.textReconstructionMismatch
        }
        return words
    }

    private static func normalize(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

public struct PrecisionRecognitionResult: Equatable, Sendable {
    public let text: String
    public let words: [PrecisionRecognizedWord]
    public let language: Locale.LanguageCode
    public let confidence: Double
    public let provenance: TranscriptionProvenance

    public init(
        text: String,
        words: [PrecisionRecognizedWord],
        language: Locale.LanguageCode,
        confidence: Double,
        provenance: TranscriptionProvenance
    ) {
        self.text = text
        self.words = words
        self.language = language
        self.confidence = confidence
        self.provenance = provenance
    }
}

public protocol PrecisionRecognizing: Sendable {
    func recognize(
        audioURL: URL,
        audioTrackIndex: Int?,
        locale: Locale,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> PrecisionRecognitionResult
}

private final class PrecisionProgressRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var lastValue = 0.0
    private let progress: @Sendable (Double) -> Void

    init(progress: @escaping @Sendable (Double) -> Void) {
        self.progress = progress
    }

    func emit(_ value: Double) {
        let clamped = min(max(value, 0), 1)
        let shouldEmit = lock.withLock { () -> Bool in
            guard clamped >= lastValue else { return false }
            lastValue = clamped
            return true
        }
        if shouldEmit { progress(clamped) }
    }
}

public enum FluidAudioOfflinePolicy {
    public static func enable() {
        ModelHub.offlineMode = true
    }
}

public struct ParakeetPrecisionModelValidator: LocalModelValidating {
    public static let validatorKey = LocalModelValidatorKey(
        rawValue: "precision-transcription.parakeet-tdt-v3"
    )
    public let key = Self.validatorKey
    public let version = 1

    public init() {}

    public func prepareAndValidate(
        release: LocalModelRelease,
        stagedPayload: URL,
        preparedOutput: URL
    ) async throws -> LocalModelPreparedPayload {
        FluidAudioOfflinePolicy.enable()
        let runtimeDirectory = preparedOutput.appending(
            path: release.runtimeDirectoryName,
            directoryHint: .isDirectory
        )
        do {
            try FileManager.default.copyItem(at: stagedPayload, to: runtimeDirectory)
            guard
                AsrModels.modelsExist(
                    at: runtimeDirectory,
                    version: .v3,
                    encoderPrecision: .int8
                )
            else {
                throw PrecisionTranscriptionError.modelCorrupt
            }
            _ = try await AsrModels.load(
                from: runtimeDirectory,
                version: .v3,
                encoderPrecision: .int8
            )
            return LocalModelPreparedPayload(payloadRoot: preparedOutput)
        } catch is CancellationError {
            throw LocalModelFailure.canceled
        } catch let failure as LocalModelFailure {
            throw failure
        } catch {
            throw LocalModelFailure.validationFailed("Parakeet could not load from local files")
        }
    }
}

public actor PrecisionTranscriptionEngine: PrecisionRecognizing {
    public static let modelID = LocalModelID(
        rawValue: "precision-transcription.parakeet-tdt-0.6b-v3-int8"
    )!
    public static let configurationRevision = "parakeet-tdt-v3-int8-aed0274-config1"

    private struct LoadedRuntime {
        let manager: AsrManager
        let lease: LocalModelLease
        let languageCode: String
    }

    private struct GateWaiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let modelManager: any LocalModelManaging
    private let audioSegmentExporter: AVFoundationAudioSegmentExporter
    private var loadedRuntime: LoadedRuntime?
    private var isRecognizing = false
    private var waiters: [GateWaiter] = []

    public init(
        modelManager: any LocalModelManaging,
        audioSegmentExporter: AVFoundationAudioSegmentExporter = AVFoundationAudioSegmentExporter()
    ) {
        self.modelManager = modelManager
        self.audioSegmentExporter = audioSegmentExporter
    }

    public func recognize(
        audioURL: URL,
        audioTrackIndex: Int?,
        locale: Locale,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> PrecisionRecognitionResult {
        try await enterSerialGate()
        do {
            let result = try await performRecognition(
                audioURL: audioURL,
                audioTrackIndex: audioTrackIndex,
                locale: locale,
                progress: progress
            )
            await leaveSerialGate()
            return result
        } catch {
            await leaveSerialGate()
            if error is CancellationError {
                throw CancellationError()
            }
            if let error = error as? PrecisionTranscriptionError {
                throw error
            }
            if let error = error as? LocalModelFailure {
                switch error {
                case .notInstalled:
                    throw PrecisionTranscriptionError.modelNotInstalled
                case .installationCorrupt:
                    throw PrecisionTranscriptionError.modelCorrupt
                default:
                    throw PrecisionTranscriptionError.inferenceFailed
                }
            }
            throw PrecisionTranscriptionError.inferenceFailed
        }
    }

    public func unload() async {
        do {
            try await enterSerialGate()
        } catch {
            return
        }
        await unloadRuntime()
        await leaveSerialGate()
    }

    private func unloadRuntime() async {
        guard let loadedRuntime else { return }
        await loadedRuntime.manager.cleanup()
        await modelManager.release(loadedRuntime.lease)
        self.loadedRuntime = nil
    }

    private func performRecognition(
        audioURL: URL,
        audioTrackIndex: Int?,
        locale: Locale,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> PrecisionRecognitionResult {
        #if !arch(arm64)
        throw PrecisionTranscriptionError.unsupportedHardware
        #endif

        let languageCode = try PrecisionTranscriptionLanguageCatalog.languageCode(for: locale)
        let fluidLanguage = try PrecisionTranscriptionLanguageCatalog.fluidLanguage(for: locale)
        let runtime = try await runtime(for: languageCode.identifier.lowercased())
        let transcriptionURL: URL
        if let audioTrackIndex {
            transcriptionURL = try await audioSegmentExporter.isolatedTrackURL(
                from: audioURL,
                audioTrackIndex: audioTrackIndex
            )
        } else {
            transcriptionURL = audioURL
        }
        defer {
            if transcriptionURL != audioURL {
                try? FileManager.default.removeItem(at: transcriptionURL)
            }
        }

        let progressRelay = PrecisionProgressRelay(progress: progress)
        let stream = await runtime.manager.transcriptionProgressStream
        let progressTask = Task {
            do {
                for try await fraction in stream {
                    progressRelay.emit(min(max(fraction, 0), 1) * 0.9)
                }
            } catch {
            }
        }
        defer { progressTask.cancel() }

        var decoderState = try TdtDecoderState()
        let result = try await runtime.manager.transcribe(
            transcriptionURL,
            decoderState: &decoderState,
            language: fluidLanguage
        )
        guard let timings = result.tokenTimings else {
            throw PrecisionTranscriptionError.missingTokenTimings
        }
        let words = try PrecisionTokenTimingMapper.map(
            timings.map {
                PrecisionTokenTiming(
                    token: $0.token,
                    start: $0.startTime,
                    end: $0.endTime,
                    confidence: Double($0.confidence)
                )
            },
            expectedText: result.text
        )
        progressRelay.emit(1)
        return PrecisionRecognitionResult(
            text: result.text,
            words: words,
            language: languageCode,
            confidence: Double(result.confidence),
            provenance: TranscriptionProvenance(
                engine: .parakeetTDTv3,
                modelRevision: runtime.lease.commit,
                configurationRevision: Self.configurationRevision
            )
        )
    }

    private func runtime(for languageCode: String) async throws -> LoadedRuntime {
        if let loadedRuntime, loadedRuntime.languageCode == languageCode {
            return loadedRuntime
        }
        await unloadRuntime()
        FluidAudioOfflinePolicy.enable()
        let lease: LocalModelLease
        do {
            lease = try await modelManager.acquire(Self.modelID)
        } catch let failure as LocalModelFailure {
            switch failure {
            case .notInstalled:
                throw PrecisionTranscriptionError.modelNotInstalled
            default:
                throw PrecisionTranscriptionError.modelCorrupt
            }
        }
        do {
            let runtimeDirectory = lease.payloadRoot.appending(
                path: "parakeet-tdt-0.6b-v3-coreml",
                directoryHint: .isDirectory
            )
            guard
                AsrModels.modelsExist(
                    at: runtimeDirectory,
                    version: .v3,
                    encoderPrecision: .int8
                )
            else {
                throw PrecisionTranscriptionError.modelCorrupt
            }
            let models = try await AsrModels.load(
                from: runtimeDirectory,
                version: .v3,
                encoderPrecision: .int8
            )
            let manager = AsrManager(
                config: ASRConfig(
                    melChunkContext: languageCode == "en",
                    dualDecodeArbitration: false
                )
            )
            try await manager.loadModels(models)
            let runtime = LoadedRuntime(manager: manager, lease: lease, languageCode: languageCode)
            loadedRuntime = runtime
            return runtime
        } catch is CancellationError {
            await modelManager.release(lease)
            throw CancellationError()
        } catch {
            await modelManager.reportInvalid(lease, reason: .loadFailed)
            await modelManager.release(lease)
            throw error
        }
    }

    private func enterSerialGate() async throws {
        try Task.checkCancellation()
        if !isRecognizing {
            isRecognizing = true
            return
        }
        let waiterID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                waiters.append(GateWaiter(id: waiterID, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(waiterID) }
        }
        try Task.checkCancellation()
    }

    private func leaveSerialGate() async {
        if waiters.isEmpty {
            await unloadRuntime()
            if waiters.isEmpty {
                isRecognizing = false
                return
            }
        }
        let next = waiters.removeFirst()
        next.continuation.resume()
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else {
            return
        }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }
}

public struct PrecisionTimedSpeechTranscriber: TimedSpeechTranscriber {
    private let engine: any PrecisionRecognizing

    public init(engine: any PrecisionRecognizing) {
        self.engine = engine
    }

    public func transcribe(
        _ request: TimedSpeechTranscriptionRequest
    ) async throws -> [TimedTranscriptSpan] {
        let result = try await engine.recognize(
            audioURL: request.audioURL,
            audioTrackIndex: request.audioTrackIndex,
            locale: request.locale,
            progress: { _ in }
        )
        return try result.words.enumerated().map { index, word in
            try word.timedSpan(id: "precision-word-\(index)", source: request.source)
        }
    }
}

public struct PrecisionCaptionSpeechTranscriber: SpeechTranscriber {
    private let engine: any PrecisionRecognizing
    private let audioTrackInspector: any AudioTrackInspector

    public init(
        engine: any PrecisionRecognizing,
        audioTrackInspector: any AudioTrackInspector = AVFoundationAudioTrackInspector()
    ) {
        self.engine = engine
        self.audioTrackInspector = audioTrackInspector
    }

    public func transcribe(
        _ request: SpeechTranscriptionRequest,
        progress: @escaping SpeechTranscriptionProgressHandler
    ) async throws -> SpeechTranscriptionResult {
        let locale = request.preferredLanguage.map { Locale(identifier: $0.identifier) } ?? .current
        let trackIndex: Int?
        if let sourceTrack = request.sourceTrack {
            let layout = try await audioTrackInspector.audioTrackLayout(in: request.audioURL)
            trackIndex = layout.firstIndex(of: sourceTrack)
        } else {
            trackIndex = nil
        }
        let result = try await engine.recognize(
            audioURL: request.audioURL,
            audioTrackIndex: trackIndex,
            locale: locale,
            progress: { progress(SpeechTranscriptionProgress(fractionCompleted: $0)) }
        )
        return SpeechTranscriptionResult(
            words: try result.words.map { try $0.captionWord() },
            language: result.language,
            provenance: result.provenance
        )
    }
}
