import AVFoundation
import Foundation

@main
enum TranscriptionBenchmarkMain {
    static func main() async {
        do {
            try await run()
        } catch {
            let message = "error: \(error.localizedDescription)\n"
            FileHandle.standardError.write(Data(message.utf8))
            writeLaunchError(message)
            exit(1)
        }
    }

    private static func run() async throws {
        let arguments = try parsedArguments()
        let manifestURL = URL(fileURLWithPath: arguments.manifest).standardizedFileURL
        let manifest = try JSONDecoder().decode(
            BenchmarkManifest.self,
            from: Data(contentsOf: manifestURL)
        )
        let manifestDirectory = manifestURL.deletingLastPathComponent()
        try validate(manifest, relativeTo: manifestDirectory)

        let report = BenchmarkReport(
            generatedAt: Date(),
            machine: BenchmarkSupport.machineName(),
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            manifestPath: manifestURL.path,
            results: try await benchmark(manifest, manifestDirectory: manifestDirectory)
        )
        BenchmarkReportPrinter.print(report)
        try write(report, to: arguments.output)
    }

    private static func benchmark(
        _ manifest: BenchmarkManifest,
        manifestDirectory: URL
    ) async throws -> [EngineResult] {
        var results: [EngineResult] = []
        for configuration in manifest.engines {
            let engine = try makeBenchmarkEngine(configuration, relativeTo: manifestDirectory)
            let loadSeconds = try await BenchmarkSupport.measure { try await engine.load() }
            var fixtureResults: [FixtureResult] = []
            for fixture in manifest.fixtures {
                fixtureResults.append(
                    try await benchmark(
                        fixture,
                        engine: engine,
                        engineID: configuration.id,
                        runs: manifest.runs,
                        relativeTo: manifestDirectory
                    )
                )
            }
            await engine.unload()
            results.append(
                EngineResult(
                    engine: configuration.id,
                    loadSeconds: loadSeconds,
                    fixtures: fixtureResults
                )
            )
        }
        return results
    }

    private static func benchmark(
        _ fixture: Fixture,
        engine: any BenchmarkEngine,
        engineID: String,
        runs: Int,
        relativeTo directory: URL
    ) async throws -> FixtureResult {
        let audioURL = BenchmarkSupport.resolve(fixture.audioPath, relativeTo: directory)
        let duration = try await AVURLAsset(url: audioURL).load(.duration).seconds
        var runSeconds: [Double] = []
        var hypothesis = ""
        for _ in 0..<runs {
            let start = ContinuousClock.now
            hypothesis = try await engine.transcribe(
                audioURL: audioURL,
                locale: Locale(identifier: fixture.locale)
            )
            runSeconds.append(BenchmarkSupport.seconds(since: start))
        }
        guard !BenchmarkSupport.normalizedWords(hypothesis).isEmpty else {
            throw BenchmarkError.emptyHypothesis(engineID, fixture.id)
        }

        let median = BenchmarkSupport.median(runSeconds)
        let referenceWords = fixture.reference.map(BenchmarkSupport.normalizedWords)
        let referenceCharacters = fixture.reference.map {
            Array(BenchmarkSupport.normalizedText($0))
        }
        return FixtureResult(
            fixture: fixture.id,
            audioSeconds: duration,
            runSeconds: runSeconds,
            medianSeconds: median,
            realTimeFactor: duration / median,
            wordErrorRate: referenceWords.map {
                BenchmarkSupport.errorRate(
                    reference: $0,
                    hypothesis: BenchmarkSupport.normalizedWords(hypothesis)
                )
            },
            characterErrorRate: referenceCharacters.map {
                BenchmarkSupport.errorRate(
                    reference: $0,
                    hypothesis: Array(BenchmarkSupport.normalizedText(hypothesis))
                )
            },
            reference: fixture.reference,
            hypothesis: hypothesis
        )
    }

    private static func validate(_ manifest: BenchmarkManifest, relativeTo directory: URL) throws {
        guard manifest.schemaVersion == 1 else {
            throw BenchmarkError.invalidManifestVersion(manifest.schemaVersion)
        }
        guard manifest.runs > 0 else {
            throw BenchmarkError.invalidRuns(manifest.runs)
        }
        var identifiers = Set<String>()
        for identifier in manifest.fixtures.map(\.id) + manifest.engines.map(\.id) {
            guard !identifier.isEmpty, identifiers.insert(identifier).inserted else {
                throw BenchmarkError.duplicateIdentifier(identifier)
            }
        }
        for fixture in manifest.fixtures {
            try requireFile(fixture.audioPath, relativeTo: directory)
        }
        for engine in manifest.engines where engine.kind != .appleSpeech {
            guard let modelDirectory = engine.modelDirectory else {
                throw BenchmarkError.missingModelDirectory(engine.id)
            }
            try requireFile(modelDirectory, relativeTo: directory)
        }
    }

    private static func requireFile(_ path: String, relativeTo directory: URL) throws {
        let resolvedPath = BenchmarkSupport.resolve(path, relativeTo: directory).path
        guard FileManager.default.fileExists(atPath: resolvedPath) else {
            throw BenchmarkError.missingFile(resolvedPath)
        }
    }

    private static func parsedArguments() throws -> (manifest: String, output: String?) {
        let arguments = Array(CommandLine.arguments.dropFirst())
        var manifest: String?
        var output: String?
        var index = 0
        while index < arguments.count {
            guard index + 1 < arguments.count else { throw BenchmarkError.usage }
            switch arguments[index] {
            case "--manifest": manifest = arguments[index + 1]
            case "--output": output = arguments[index + 1]
            default: throw BenchmarkError.usage
            }
            index += 2
        }
        guard let manifest else { throw BenchmarkError.usage }
        return (manifest, output)
    }

    private static func write(_ report: BenchmarkReport, to output: String?) throws {
        guard let output else { return }
        let outputURL = URL(fileURLWithPath: output).standardizedFileURL
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: outputURL, options: .atomic)
        print("\nJSON: \(outputURL.path)")
    }

    private static func writeLaunchError(_ message: String) {
        let arguments = CommandLine.arguments
        guard let outputIndex = arguments.firstIndex(of: "--output"),
            arguments.indices.contains(outputIndex + 1)
        else {
            return
        }
        let errorURL = URL(fileURLWithPath: arguments[outputIndex + 1] + ".error")
        try? Data(message.utf8).write(to: errorURL, options: .atomic)
    }
}
