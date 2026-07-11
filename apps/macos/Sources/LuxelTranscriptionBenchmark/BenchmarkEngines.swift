import AVFoundation
import CoreML
import FluidAudio
import Foundation
import LuxelCore

actor AppleSpeechBenchmarkEngine: BenchmarkEngine {
    private let transcriber = AppleSpeechTranscriptExtractor()

    func load() {}

    func transcribe(audioURL: URL, locale: Locale) async throws -> String {
        let spans = try await transcriber.transcribe(
            TimedSpeechTranscriptionRequest(
                audioURL: audioURL,
                locale: locale,
                source: nil,
                audioTrackIndex: nil,
                transcriptionProvenance: .appleSpeech
            )
        )
        return spans.map(\.text).joined(separator: " ")
    }

    func unload() {}
}

actor ParakeetBenchmarkEngine: BenchmarkEngine {
    private let configuration: Engine
    private let modelDirectory: URL
    private var manager: AsrManager?

    init(configuration: Engine, modelDirectory: URL) {
        self.configuration = configuration
        self.modelDirectory = modelDirectory
    }

    func load() async throws {
        let version = try modelVersion(configuration.modelVersion ?? "v3")
        let precision = try encoderPrecision(configuration.encoderPrecision ?? "int8")
        let models = try await AsrModels.load(
            from: modelDirectory,
            version: version,
            encoderPrecision: precision,
            encoderComputeUnits: try parsedComputeUnits(configuration.encoderComputeUnits)
        )
        let manager = AsrManager(
            config: ASRConfig(
                tdtConfig: TdtConfig(blankId: version.blankId),
                encoderHiddenSize: version.encoderHiddenSize,
                melChunkContext: configuration.melChunkContext ?? true,
                dualDecodeArbitration: false
            )
        )
        try await manager.loadModels(models)
        self.manager = manager
    }

    func transcribe(audioURL: URL, locale: Locale) async throws -> String {
        guard let manager else {
            throw BenchmarkError.engineNotLoaded(configuration.id)
        }
        let languageCode = locale.language.languageCode?.identifier.lowercased()
        let language = languageCode.flatMap(Language.init(rawValue:))
        var decoderState = try TdtDecoderState()
        return try await manager.transcribe(
            audioURL,
            decoderState: &decoderState,
            language: language
        ).text
    }

    func unload() async {
        await manager?.cleanup()
        manager = nil
    }

    private func modelVersion(_ value: String) throws -> AsrModelVersion {
        switch value {
        case "v2": .v2
        case "v3": .v3
        case "tdtCtc110m": .tdtCtc110m
        case "tdtJa": .tdtJa
        default: throw BenchmarkError.invalidModelVersion(value)
        }
    }

    private func encoderPrecision(_ value: String) throws -> ParakeetEncoderPrecision {
        guard let precision = ParakeetEncoderPrecision(rawValue: value) else {
            throw BenchmarkError.invalidEncoderPrecision(value)
        }
        return precision
    }
}

actor LuxelPrecisionBenchmarkEngine: BenchmarkEngine {
    private let engine: PrecisionTranscriptionEngine

    init(modelsRoot: URL) throws {
        let manager = try makeProductionModelManager(modelsRoot: modelsRoot)
        engine = PrecisionTranscriptionEngine(modelManager: manager)
    }

    func load() {}

    func transcribe(audioURL: URL, locale: Locale) async throws -> String {
        try await engine.recognize(
            audioURL: audioURL,
            audioTrackIndex: nil,
            locale: locale
        ).text
    }

    func unload() async {
        await engine.unload()
    }
}

actor ParakeetUnifiedBenchmarkEngine: BenchmarkEngine {
    private let manager: UnifiedAsrManager
    private let modelDirectory: URL

    init(configuration: Engine, modelDirectory: URL) throws {
        let precisionValue = configuration.encoderPrecision ?? "int8"
        guard let precision = UnifiedEncoderPrecision(rawValue: precisionValue) else {
            throw BenchmarkError.invalidEncoderPrecision(precisionValue)
        }
        let modelConfiguration = MLModelConfiguration()
        modelConfiguration.computeUnits = try parsedComputeUnits(
            configuration.encoderComputeUnits
        ) ?? .cpuAndNeuralEngine
        manager = UnifiedAsrManager(
            configuration: modelConfiguration,
            encoderPrecision: precision
        )
        self.modelDirectory = modelDirectory
    }

    func load() async throws {
        try await manager.loadModels(from: modelDirectory)
    }

    func transcribe(audioURL: URL, locale: Locale) async throws -> String {
        let audioFile = try AVAudioFile(forReading: audioURL)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: audioFile.processingFormat,
            frameCapacity: AVAudioFrameCount(audioFile.length)
        ) else {
            throw BenchmarkError.audioBufferCreationFailed(audioURL.path)
        }
        try audioFile.read(into: buffer)
        return try await manager.transcribe(buffer)
    }

    func unload() async {
        await manager.cleanup()
    }
}

final class EmptyTranscriptCache: TranscriptCache, @unchecked Sendable {
    func load(for request: AudioTranscriptRequest) throws -> TurnSegmentedTranscript? { nil }
    func save(_ transcript: TurnSegmentedTranscript, for request: AudioTranscriptRequest) throws {}
}

actor LuxelPipelineBenchmarkEngine: BenchmarkEngine {
    private let service: LocalAudioTranscriptService
    private let provenance: TranscriptionProvenance
    private let semanticTurns: Bool
    private let diarize: Bool
    private let engine: PrecisionTranscriptionEngine

    init(
        modelsRoot: URL,
        speakerModelsDirectory: URL?,
        semanticTurns: Bool,
        diarize: Bool
    ) throws {
        let manager = try makeProductionModelManager(modelsRoot: modelsRoot)
        let engine = PrecisionTranscriptionEngine(modelManager: manager)
        let provenance = TranscriptionProvenance(
            engine: .parakeetTDTv3,
            modelRevision: "aed02740059203c4a87495924f685de3722ae9ce",
            configurationRevision: PrecisionTranscriptionEngine.configurationRevision
        )
        let speakerModelStore = speakerModelsDirectory.map {
            FluidAudioSpeakerDiarizationModelStore(modelsDirectory: $0)
        }
        self.engine = engine
        self.provenance = provenance
        self.semanticTurns = semanticTurns
        self.diarize = diarize
        service = LocalAudioTranscriptService(
            transcriber: PrecisionTimedSpeechTranscriber(engine: engine),
            turnSegmenter: AppleIntelligenceTurnSegmenter(),
            turnSegmentationMode: { semanticTurns ? .semantic : .raw },
            speakerDiarizationMode: { diarize ? .enabled : .disabled },
            transcriptionProvenance: { provenance },
            cache: EmptyTranscriptCache(),
            audioTrackInspector: AVFoundationAudioTrackInspector(),
            speakerDiarizer: speakerModelsDirectory.map {
                FluidAudioSpeakerDiarizer(modelsDirectory: $0)
            },
            speakerModelStore: speakerModelStore
        )
    }

    func load() {}

    func transcribe(audioURL: URL, locale: Locale) async throws -> String {
        let transcript = try await service.transcript(
            for: AudioTranscriptRequest(
                audioURL: audioURL,
                locale: locale,
                sourceContext: .unknown,
                turnSegmentationMode: semanticTurns ? .semantic : .raw,
                speakerDiarizationMode: diarize ? .enabled : .disabled,
                transcriptionProvenance: provenance
            )
        )
        return transcript?.spans.map(\.text).joined(separator: " ") ?? ""
    }

    func unload() async {
        await engine.unload()
    }
}

func makeBenchmarkEngine(
    _ configuration: Engine,
    relativeTo directory: URL
) throws -> any BenchmarkEngine {
    switch configuration.kind {
    case .appleSpeech:
        AppleSpeechBenchmarkEngine()
    case .luxelPipeline:
        try LuxelPipelineBenchmarkEngine(
            modelsRoot: requiredModelDirectory(configuration, relativeTo: directory),
            speakerModelsDirectory: configuration.speakerModelDirectory.map {
                BenchmarkSupport.resolve($0, relativeTo: directory)
            },
            semanticTurns: configuration.semanticTurns ?? false,
            diarize: configuration.diarize ?? false
        )
    case .luxelPrecision:
        try LuxelPrecisionBenchmarkEngine(
            modelsRoot: requiredModelDirectory(configuration, relativeTo: directory)
        )
    case .parakeet:
        ParakeetBenchmarkEngine(
            configuration: configuration,
            modelDirectory: try requiredModelDirectory(configuration, relativeTo: directory)
        )
    case .parakeetUnified:
        try ParakeetUnifiedBenchmarkEngine(
            configuration: configuration,
            modelDirectory: requiredModelDirectory(configuration, relativeTo: directory)
        )
    }
}

private func requiredModelDirectory(_ engine: Engine, relativeTo directory: URL) throws -> URL {
    guard let path = engine.modelDirectory else {
        throw BenchmarkError.missingModelDirectory(engine.id)
    }
    return BenchmarkSupport.resolve(path, relativeTo: directory)
}

private func makeProductionModelManager(modelsRoot: URL) throws -> LocalModelManager {
    FluidAudioOfflinePolicy.enable()
    let appVersion = Bundle.main.object(
        forInfoDictionaryKey: "CFBundleShortVersionString"
    ) as? String ?? "1.0.0"
    let appBuild = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    let validator = ParakeetPrecisionModelValidator()
    let catalog = try BundledLocalModelCatalog.production(
        registeredValidatorKeys: [validator.key],
        attributionIdentifiers: ["fluidinference-parakeet-tdt-0.6b-v3-coreml"],
        currentAppVersion: appVersion
    )
    return try LocalModelManager(
        catalogProvider: catalog,
        validators: [validator],
        downloader: HuggingFaceModelArtifactDownloadClient(
            userAgent: "LuxelTranscriptionBenchmark/\(appVersion)"
        ),
        verifier: SHA256ArtifactVerifier(),
        repository: ApplicationSupportLocalModelRepository(
            root: modelsRoot,
            appVersion: appVersion,
            appBuild: appBuild
        )
    )
}

private func parsedComputeUnits(_ value: String?) throws -> MLComputeUnits? {
    switch value {
    case nil: nil
    case "all": .all
    case "cpuOnly": .cpuOnly
    case "cpuAndGPU": .cpuAndGPU
    case "cpuAndNeuralEngine": .cpuAndNeuralEngine
    case .some(let value): throw BenchmarkError.invalidComputeUnits(value)
    }
}
