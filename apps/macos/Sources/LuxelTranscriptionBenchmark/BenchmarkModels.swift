import Foundation

struct BenchmarkManifest: Decodable {
    let schemaVersion: Int
    let runs: Int
    let fixtures: [Fixture]
    let engines: [Engine]
}

struct Fixture: Decodable {
    let id: String
    let audioPath: String
    let reference: String?
    let locale: String
}

struct Engine: Decodable {
    let id: String
    let kind: EngineKind
    let modelDirectory: String?
    let modelVersion: String?
    let encoderPrecision: String?
    let encoderComputeUnits: String?
    let melChunkContext: Bool?
}

enum EngineKind: String, Decodable {
    case appleSpeech
    case parakeet
    case parakeetUnified
}

struct BenchmarkReport: Encodable {
    let generatedAt: Date
    let machine: String
    let operatingSystem: String
    let manifestPath: String
    let results: [EngineResult]
}

struct EngineResult: Encodable {
    let engine: String
    let loadSeconds: Double
    let fixtures: [FixtureResult]
}

struct FixtureResult: Encodable {
    let fixture: String
    let audioSeconds: Double
    let runSeconds: [Double]
    let medianSeconds: Double
    let realTimeFactor: Double
    let wordErrorRate: Double?
    let characterErrorRate: Double?
    let reference: String?
    let hypothesis: String
}

protocol BenchmarkEngine: Sendable {
    func load() async throws
    func transcribe(audioURL: URL, locale: Locale) async throws -> String
    func unload() async
}

enum BenchmarkError: LocalizedError {
    case usage
    case invalidManifestVersion(Int)
    case invalidRuns(Int)
    case duplicateIdentifier(String)
    case missingFile(String)
    case missingModelDirectory(String)
    case engineNotLoaded(String)
    case invalidModelVersion(String)
    case invalidEncoderPrecision(String)
    case invalidComputeUnits(String)
    case audioBufferCreationFailed(String)
    case emptyHypothesis(String, String)

    var errorDescription: String? {
        switch self {
        case .usage:
            "Usage: luxel-transcription-benchmark --manifest <file> [--output <file>]"
        case .invalidManifestVersion(let version):
            "Unsupported benchmark manifest schema version: \(version)."
        case .invalidRuns(let runs):
            "Benchmark runs must be greater than zero, got \(runs)."
        case .duplicateIdentifier(let identifier):
            "Benchmark identifiers must be unique: \(identifier)."
        case .missingFile(let path):
            "Benchmark file does not exist: \(path)."
        case .missingModelDirectory(let engine):
            "Parakeet engine \(engine) is missing modelDirectory."
        case .engineNotLoaded(let engine):
            "Benchmark engine is not loaded: \(engine)."
        case .invalidModelVersion(let version):
            "Unsupported Parakeet modelVersion: \(version)."
        case .invalidEncoderPrecision(let precision):
            "Unsupported Parakeet encoderPrecision: \(precision)."
        case .invalidComputeUnits(let units):
            "Unsupported encoderComputeUnits: \(units)."
        case .audioBufferCreationFailed(let path):
            "Could not create an audio buffer for \(path)."
        case .emptyHypothesis(let engine, let fixture):
            "Engine \(engine) returned an empty transcript for \(fixture)."
        }
    }
}
