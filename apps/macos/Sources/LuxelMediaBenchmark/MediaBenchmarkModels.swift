import Foundation
import LuxelCodecAV1
import LuxelCodecWebM
import LuxelCore

struct BenchmarkArguments {
    let fixturePath: String
    let outputPath: String
    let runs: Int

    static func parse(_ arguments: ArraySlice<String>) throws -> BenchmarkArguments {
        var fixturePath: String?
        var outputPath: String?
        var runs = 2
        var index = arguments.startIndex

        while index < arguments.endIndex {
            let option = arguments[index]
            index = arguments.index(after: index)
            guard index < arguments.endIndex else {
                throw MediaBenchmarkError.usage
            }
            let value = arguments[index]
            index = arguments.index(after: index)
            switch option {
            case "--fixture":
                guard fixturePath == nil else { throw MediaBenchmarkError.usage }
                fixturePath = value
            case "--output":
                guard outputPath == nil else { throw MediaBenchmarkError.usage }
                outputPath = value
            case "--runs":
                guard let parsedRuns = Int(value), (1...5).contains(parsedRuns) else {
                    throw MediaBenchmarkError.invalidRunCount(value)
                }
                runs = parsedRuns
            default:
                throw MediaBenchmarkError.usage
            }
        }

        guard let fixturePath, let outputPath else {
            throw MediaBenchmarkError.usage
        }
        return BenchmarkArguments(fixturePath: fixturePath, outputPath: outputPath, runs: runs)
    }
}

struct MediaBenchmarkCase {
    enum ExporterKind {
        case native
        case webM
        case av1
    }

    enum Validation {
        case assetDuration
        case gifFrames
        case webM
    }

    let id: String
    let format: ExportFormat
    let duration: TimeInterval
    let frameRate: FrameRate
    let pixelSize: PixelSize
    let minimumThroughput: Double
    let minimumOutputBytes: Int64
    let requiredMarkers: [String]
    let exporterKind: ExporterKind
    let validation: Validation

    var exporter: any MediaExporter {
        switch exporterKind {
        case .native:
            NativeMediaExporter()
        case .webM:
            WebMMediaExporter()
        case .av1:
            AV1MediaExporter()
        }
    }

    func request(fixtureURL: URL) throws -> ExportRequest {
        try ExportRequest(
            inputFileURL: fixtureURL,
            format: format,
            pixelSize: pixelSize,
            frameRate: frameRate,
            timeRange: TimeRange(start: 0, end: duration),
            shouldMute: false,
            shouldCrop: false,
            quality: .balanced
        )
    }

    static func all() throws -> [MediaBenchmarkCase] {
        [
            MediaBenchmarkCase(
                id: "mp4-h264-balanced",
                format: .mp4,
                duration: 5,
                frameRate: .fps30,
                pixelSize: .fullHD1920x1080,
                minimumThroughput: 1,
                minimumOutputBytes: 1_024,
                requiredMarkers: ["avc1", "mp4a"],
                exporterKind: .native,
                validation: .assetDuration
            ),
            MediaBenchmarkCase(
                id: "gif-balanced",
                format: .gif,
                duration: 2,
                frameRate: try FrameRate(15),
                pixelSize: .fullHD1920x1080,
                minimumThroughput: 0.5,
                minimumOutputBytes: 1_024,
                requiredMarkers: [],
                exporterKind: .native,
                validation: .gifFrames
            ),
            MediaBenchmarkCase(
                id: "webm-vp9-opus-balanced",
                format: .webm,
                duration: 5,
                frameRate: .fps30,
                pixelSize: .fullHD1920x1080,
                minimumThroughput: 0.5,
                minimumOutputBytes: 1_024,
                requiredMarkers: ["webm", "V_VP9", "A_OPUS"],
                exporterKind: .webM,
                validation: .webM
            ),
            MediaBenchmarkCase(
                id: "av1-aac-balanced",
                format: .av1,
                duration: 5,
                frameRate: .fps30,
                pixelSize: .fullHD1920x1080,
                minimumThroughput: 0.3,
                minimumOutputBytes: 1_024,
                requiredMarkers: ["av01", "mp4a"],
                exporterKind: .av1,
                validation: .assetDuration
            )
        ]
    }
}

struct MediaBenchmarkReport: Encodable {
    let schemaVersion = 1
    let fixtureSHA256: String
    let fixture: String
    let machine: String
    let operatingSystem: String
    let runs: Int
    let results: [MediaBenchmarkCaseResult]
}

struct MediaBenchmarkCaseResult: Encodable {
    let id: String
    let format: String
    let sourceSeconds: Double
    let framesPerSecond: Int
    let pixelWidth: Int
    let pixelHeight: Int
    let runSeconds: [Double]
    let bestSeconds: Double
    let throughput: Double
    let minimumThroughput: Double
    let outputBytes: Int64
    let passed: Bool
}

enum MediaBenchmarkError: LocalizedError {
    case usage
    case invalidRunCount(String)
    case missingFixture(String)
    case fixtureChecksumMismatch(String)
    case invalidOutput(String)
    case performanceFloorMissed(String)

    var errorDescription: String? {
        switch self {
        case .usage:
            "Usage: luxel-media-benchmark --fixture <path> --output <path> [--runs 1...5]"
        case let .invalidRunCount(value):
            "Invalid run count: \(value)"
        case let .missingFixture(path):
            "Media benchmark fixture is missing: \(path)"
        case let .fixtureChecksumMismatch(actual):
            "Media benchmark fixture checksum mismatch: \(actual)"
        case let .invalidOutput(message):
            message
        case let .performanceFloorMissed(cases):
            "Media benchmark performance floor missed: \(cases)"
        }
    }
}
