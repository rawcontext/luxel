import FluidAudio
import Foundation

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
}

private extension PrecisionTranscriptionEngine {
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
        let transcriptionURL = try await transcriptionURL(
            audioURL: audioURL,
            audioTrackIndex: audioTrackIndex
        )
        defer {
            if transcriptionURL != audioURL {
                try? FileManager.default.removeItem(at: transcriptionURL)
            }
        }

        let progressRelay = PrecisionProgressRelay(progress: progress)
        let progressTask = await transcriptionProgressTask(
            manager: runtime.manager,
            relay: progressRelay
        )
        defer { progressTask.cancel() }

        var decoderState = try TdtDecoderState()
        let result = try await runtime.manager.transcribe(
            transcriptionURL,
            decoderState: &decoderState,
            language: fluidLanguage
        )
        let words = try PrecisionTokenTimingMapper.map(
            (result.tokenTimings ?? []).map {
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

    private func transcriptionProgressTask(
        manager: AsrManager,
        relay: PrecisionProgressRelay
    ) async -> Task<Void, Never> {
        let stream = await manager.transcriptionProgressStream
        return Task {
            do {
                for try await fraction in stream {
                    relay.emit(min(max(fraction, 0), 1) * 0.9)
                }
            } catch {
            }
        }
    }

    private func transcriptionURL(
        audioURL: URL,
        audioTrackIndex: Int?
    ) async throws -> URL {
        guard let audioTrackIndex else {
            return audioURL
        }
        return try await audioSegmentExporter.isolatedTrackURL(
            from: audioURL,
            audioTrackIndex: audioTrackIndex
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
            let runtime = try await loadRuntime(lease: lease, languageCode: languageCode)
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

    private func loadRuntime(
        lease: LocalModelLease,
        languageCode: String
    ) async throws -> LoadedRuntime {
        let runtimeDirectory = lease.payloadRoot.appending(
            path: ParakeetPrecisionModelValidator.runtimeDirectoryName,
            directoryHint: .isDirectory
        )
        guard AsrModels.modelsExist(
            at: runtimeDirectory,
            version: .v3,
            encoderPrecision: .int8
        ) else {
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
        return LoadedRuntime(manager: manager, lease: lease, languageCode: languageCode)
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
        try await transcribe(request, progress: { _ in })
    }

    public func transcribe(
        _ request: TimedSpeechTranscriptionRequest,
        progress: @escaping SpeechTranscriptionProgressHandler
    ) async throws -> [TimedTranscriptSpan] {
        let result = try await engine.recognize(
            audioURL: request.audioURL,
            audioTrackIndex: request.audioTrackIndex,
            locale: request.locale,
            progress: {
                progress(SpeechTranscriptionProgress(fractionCompleted: $0))
            }
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
