import AVFoundation
import Foundation
import LuxelCore
import LuxelTestSupport
import Testing

@testable import LuxelPresentation

struct StubExportAudioPreparer: ExportAudioPreparing {
    func prepareAudio(
        for requests: [ExportRequest],
        progress: ExportAudioPreparationProgressHandler?
    ) async throws -> PreparedExportAudioSet {
        for (index, request) in requests.enumerated() where request.requiresAudioPreparation {
            await progress?(
                ExportAudioPreparationProgress(requestIndices: [index], progress: 1)
            )
        }
        return PreparedExportAudioSet()
    }
}

enum StubError: Error {
    case importFailed
    case trashFailed
}

final class SpyErrorReporter: ErrorReporter {
    struct Record: Equatable {
        let context: String
        let description: String
    }

    private(set) var records: [Record] = []

    func record(_ error: any Error, context: String) {
        records.append(
            Record(
                context: context,
                description: String(describing: error)
            ))
    }
}

struct StubMetadataReader: MediaMetadataReader {
    let hasAlpha: Bool
    let source: SourceMedia?

    init(hasAlpha: Bool = false, source: SourceMedia? = nil) {
        self.hasAlpha = hasAlpha
        self.source = source
    }

    func readSourceMedia(at fileURL: URL) async throws -> SourceMedia {
        if let source {
            return source
        }

        return try SourceMedia(
            fileURL: fileURL,
            duration: 12,
            pixelSize: PixelSize(width: 1280, height: 720),
            nominalFrameRate: FrameRate(30),
            hasAudio: true,
            hasAlpha: hasAlpha
        )
    }
}

struct StubMediaExporter: MediaExporter {
    let exportedMedia: ExportedMedia?

    init(exportedMedia: ExportedMedia? = nil) {
        self.exportedMedia = exportedMedia
    }

    func export(
        _ input: MediaExportInput,
        to outputFileURL: URL,
        progress: MediaExportProgressHandler?
    ) async throws -> ExportedMedia {
        let request = input.request
        if let exportedMedia {
            return exportedMedia
        }

        return ExportedMedia(
            fileURL: outputFileURL,
            format: request.format,
            pixelSize: try request.outputPixelSize,
            shouldMute: request.outputShouldMute
        )
    }
}

actor SpyMediaExporter: MediaExporter {
    private var captured: [(request: ExportRequest, outputFileURL: URL)] = []

    func export(
        _ input: MediaExportInput,
        to outputFileURL: URL,
        progress: MediaExportProgressHandler?
    ) async throws -> ExportedMedia {
        let request = input.request
        captured.append((request, outputFileURL))
        return ExportedMedia(
            fileURL: outputFileURL,
            format: request.format,
            pixelSize: try request.outputPixelSize,
            shouldMute: request.outputShouldMute
        )
    }

    func capturedExports() -> [(request: ExportRequest, outputFileURL: URL)] {
        captured
    }
}

struct StubPassthroughExporter: PassthroughExporter {
    func export(_ request: PassthroughExportRequest) async throws -> PassthroughExportResult {
        PassthroughExportResult(fileURL: request.outputFileURL)
    }
}

typealias SpyFrameGrabber = TestFrameGrabberSpy

struct StubFrameGrabber: FrameGrabber {
    func grab(_ request: FrameGrabRequest) async throws -> FrameGrabImageData {
        try FrameGrabImageData(
            data: Data([0x89, 0x50, 0x4e, 0x47]),
            pixelSize: PixelSize(width: 1, height: 1)
        )
    }
}

typealias SpyFrameGrabFileWriter = TestFrameGrabFileWriterSpy

struct StubExportSizeEstimator: ExportSizeEstimator {
    func estimate(_ request: ExportRequest) async throws -> ExportEstimate {
        try ExportEstimate(bytes: 1_500_000, confidence: .modeled)
    }
}

struct StubFailingExportSizeEstimator: ExportSizeEstimator {
    func estimate(_ request: ExportRequest) async throws -> ExportEstimate {
        throw StubError.importFailed
    }
}

struct DelayedFormatExportSizeEstimator: ExportSizeEstimator {
    let delayedFormat: ExportFormat

    func estimate(_ request: ExportRequest) async throws -> ExportEstimate {
        if request.format == delayedFormat {
            try await Task.sleep(for: .milliseconds(500))
        }

        return try ExportEstimate(bytes: 1_500_000, confidence: .modeled)
    }
}
