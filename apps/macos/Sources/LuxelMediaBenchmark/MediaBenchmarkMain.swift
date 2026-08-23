import AVFoundation
import CryptoKit
import Foundation
import ImageIO
import LuxelCore

private let expectedFixtureSHA256 = "40f7319a4714d0e138999c94959be2c966d25ab3ccf0c71e5c702d4a266755ec"

@main
enum MediaBenchmarkMain {
    static func main() async {
        do {
            try await run()
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    private static func run() async throws {
        let arguments = try BenchmarkArguments.parse(CommandLine.arguments.dropFirst())
        let fixtureURL = URL(fileURLWithPath: arguments.fixturePath).standardizedFileURL
        let resultsURL = URL(fileURLWithPath: arguments.outputPath).standardizedFileURL
        try validateFixture(at: fixtureURL)

        let outputDirectory = resultsURL.deletingLastPathComponent().appending(path: "outputs")
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        var results: [MediaBenchmarkCaseResult] = []
        for benchmarkCase in try MediaBenchmarkCase.all() {
            let result = try await benchmark(
                benchmarkCase,
                fixtureURL: fixtureURL,
                outputDirectory: outputDirectory,
                runs: arguments.runs
            )
            results.append(result)
            printResult(result)
        }

        let report = MediaBenchmarkReport(
            fixtureSHA256: expectedFixtureSHA256,
            fixture: "Tests/Fixtures/input@2x.mp4",
            machine: ProcessInfo.processInfo.hostName,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            runs: arguments.runs,
            results: results
        )
        try write(report, to: resultsURL)

        let regressions = results.filter { !$0.passed }
        guard regressions.isEmpty else {
            throw MediaBenchmarkError.performanceFloorMissed(
                regressions.map(\.id).joined(separator: ", ")
            )
        }
        print("Results: \(resultsURL.path)")
    }

    private static func benchmark(
        _ benchmarkCase: MediaBenchmarkCase,
        fixtureURL: URL,
        outputDirectory: URL,
        runs: Int
    ) async throws -> MediaBenchmarkCaseResult {
        let outputURL = outputDirectory
            .appending(path: benchmarkCase.id)
            .appendingPathExtension(benchmarkCase.format.fileExtension)
        let request = try benchmarkCase.request(fixtureURL: fixtureURL)
        var runSeconds: [Double] = []

        for _ in 0..<runs {
            try? FileManager.default.removeItem(at: outputURL)
            let start = ContinuousClock.now
            let exported = try await benchmarkCase.exporter.export(request, to: outputURL)
            let elapsed = seconds(from: start.duration(to: .now))
            try await validate(
                exported,
                request: request,
                benchmarkCase: benchmarkCase,
                outputURL: outputURL
            )
            runSeconds.append(elapsed)
        }

        let bestSeconds = try required(runSeconds.min(), "\(benchmarkCase.id): no timing result")
        let bytes = try fileSize(at: outputURL)
        let throughput = benchmarkCase.duration / bestSeconds
        return MediaBenchmarkCaseResult(
            id: benchmarkCase.id,
            format: benchmarkCase.format.rawValue,
            sourceSeconds: benchmarkCase.duration,
            framesPerSecond: benchmarkCase.frameRate.framesPerSecond,
            pixelWidth: benchmarkCase.pixelSize.width,
            pixelHeight: benchmarkCase.pixelSize.height,
            runSeconds: runSeconds,
            bestSeconds: bestSeconds,
            throughput: throughput,
            minimumThroughput: benchmarkCase.minimumThroughput,
            outputBytes: bytes,
            passed: throughput >= benchmarkCase.minimumThroughput
        )
    }

    private static func validate(
        _ exported: ExportedMedia,
        request: ExportRequest,
        benchmarkCase: MediaBenchmarkCase,
        outputURL: URL
    ) async throws {
        guard exported.fileURL == outputURL,
              exported.format == benchmarkCase.format,
              exported.pixelSize == request.pixelSize
        else {
            throw MediaBenchmarkError.invalidOutput("\(benchmarkCase.id): exporter metadata mismatch")
        }
        guard try fileSize(at: outputURL) >= benchmarkCase.minimumOutputBytes else {
            throw MediaBenchmarkError.invalidOutput("\(benchmarkCase.id): output is unexpectedly small")
        }

        let data = try Data(contentsOf: outputURL)
        for marker in benchmarkCase.requiredMarkers where data.range(of: Data(marker.utf8)) == nil {
            throw MediaBenchmarkError.invalidOutput("\(benchmarkCase.id): missing \(marker) marker")
        }

        switch benchmarkCase.validation {
        case .assetDuration:
            let duration = try await AVURLAsset(url: outputURL).load(.duration).seconds
            let tolerance = 1 / Double(benchmarkCase.frameRate.framesPerSecond) + 0.05
            guard duration.isFinite, abs(duration - benchmarkCase.duration) <= tolerance else {
                throw MediaBenchmarkError.invalidOutput(
                    "\(benchmarkCase.id): duration \(duration)s, expected \(benchmarkCase.duration)s"
                )
            }
        case .gifFrames:
            guard data.starts(with: Data("GIF8".utf8)),
                  let source = CGImageSourceCreateWithURL(outputURL as CFURL, nil)
            else {
                throw MediaBenchmarkError.invalidOutput("\(benchmarkCase.id): invalid GIF")
            }
            let expectedFrames = Int(
                benchmarkCase.duration * Double(benchmarkCase.frameRate.framesPerSecond)
            )
            guard CGImageSourceGetCount(source) == expectedFrames else {
                throw MediaBenchmarkError.invalidOutput(
                    "\(benchmarkCase.id): unexpected GIF frame count"
                )
            }
        case .webM:
            guard data.starts(with: Data([0x1A, 0x45, 0xDF, 0xA3])) else {
                throw MediaBenchmarkError.invalidOutput("\(benchmarkCase.id): invalid EBML header")
            }
        }
    }

    private static func validateFixture(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw MediaBenchmarkError.missingFixture(url.path)
        }
        let digest = SHA256.hash(data: try Data(contentsOf: url))
            .map { String(format: "%02x", $0) }
            .joined()
        guard digest == expectedFixtureSHA256 else {
            throw MediaBenchmarkError.fixtureChecksumMismatch(digest)
        }
    }

    private static func write(_ report: MediaBenchmarkReport, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(report).write(to: url, options: .atomic)
    }

    private static func printResult(_ result: MediaBenchmarkCaseResult) {
        let name = result.id.padding(toLength: 28, withPad: " ", startingAt: 0)
        let verdict = result.passed ? "PASS" : "FAIL"
        print(
            String(
                format: "%@ best %6.2fs  %5.2fx (floor %4.2fx)  %8lld bytes  %@",
                name,
                result.bestSeconds,
                result.throughput,
                result.minimumThroughput,
                result.outputBytes,
                verdict as NSString
            )
        )
    }

    private static func seconds(from duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    private static func fileSize(at url: URL) throws -> Int64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try required(attributes[.size] as? NSNumber, "Missing file size").int64Value
    }

    private static func required<Value>(_ value: Value?, _ message: String) throws -> Value {
        guard let value else {
            throw MediaBenchmarkError.invalidOutput(message)
        }
        return value
    }
}
