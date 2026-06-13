import Foundation
import LuxelCore
import Testing

@Suite("Passthrough export service")
struct PassthroughExportServiceTests {
    @Test("copies original file byte for byte")
    func copiesOriginalFileByteForByte() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appending(path: "source.mp4")
        let outputURL = directory
            .appending(path: "exports", directoryHint: .isDirectory)
            .appending(path: "source Original.mp4")
        let bytes = Data([0, 1, 2, 3, 5, 8, 13, 21])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try bytes.write(to: sourceURL)

        let service = PassthroughExportService(fileSystem: LocalFileSystem())
        let result = try await service.export(PassthroughExportRequest(
            inputFileURL: sourceURL,
            outputFileURL: outputURL
        ))

        #expect(result.fileURL == outputURL)
        #expect(try Data(contentsOf: outputURL) == bytes)
    }

    @Test("same source and destination is a no-op")
    func sameSourceAndDestinationIsNoop() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appending(path: "source.mp4")
        let bytes = Data([89, 55, 34])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try bytes.write(to: sourceURL)

        let service = PassthroughExportService(fileSystem: LocalFileSystem())
        let result = try await service.export(PassthroughExportRequest(
            inputFileURL: sourceURL,
            outputFileURL: sourceURL
        ))

        #expect(result.fileURL == sourceURL)
        #expect(try Data(contentsOf: sourceURL) == bytes)
    }

    @Test("trimmed passthrough delegates to exporter")
    func trimmedPassthroughDelegatesToExporter() async throws {
        let fileSystem = SpyFileSystem()
        let exporter = SpyPassthroughExporter()
        let service = PassthroughExportService(fileSystem: fileSystem, trimmedExporter: exporter)
        let request = try PassthroughExportRequest(
            inputFileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            outputFileURL: URL(fileURLWithPath: "/tmp/output.mp4"),
            timeRange: TimeRange(start: 1, end: 2)
        )

        let result = try await service.export(request)

        #expect(result.fileURL.path == "/tmp/output.mp4")
        #expect(fileSystem.createdDirectories.map(\.path) == ["/tmp"])
        #expect(fileSystem.copiedFiles.isEmpty)
        #expect(await exporter.requests() == [request])
    }

    @Test("trimmed passthrough requires exporter")
    func trimmedPassthroughRequiresExporter() async throws {
        let service = PassthroughExportService(fileSystem: LocalFileSystem())
        let request = try PassthroughExportRequest(
            inputFileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            outputFileURL: URL(fileURLWithPath: "/tmp/output.mp4"),
            timeRange: TimeRange(start: 1, end: 2)
        )

        await #expect(throws: PassthroughExportError.trimmedPassthroughUnavailable) {
            _ = try await service.export(request)
        }
    }

    @Test("trimmed passthrough rejects same source and destination")
    func trimmedPassthroughRejectsSameSourceAndDestination() async throws {
        let sourceURL = URL(fileURLWithPath: "/tmp/source.mp4")
        let service = PassthroughExportService(
            fileSystem: LocalFileSystem(),
            trimmedExporter: SpyPassthroughExporter()
        )
        let request = try PassthroughExportRequest(
            inputFileURL: sourceURL,
            outputFileURL: sourceURL,
            timeRange: TimeRange(start: 1, end: 2)
        )

        await #expect(throws: PassthroughExportError.sameSourceAndDestination) {
            _ = try await service.export(request)
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "luxel-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}

private final class SpyFileSystem: FileSystem, @unchecked Sendable {
    private let lock = NSLock()
    private var capturedCreatedDirectories: [URL] = []
    private var capturedCopiedFiles: [CopiedFile] = []

    var createdDirectories: [URL] {
        lock.withLock {
            capturedCreatedDirectories
        }
    }

    var copiedFiles: [CopiedFile] {
        lock.withLock {
            capturedCopiedFiles
        }
    }

    func fileExists(at url: URL) -> Bool {
        false
    }

    func createDirectory(at url: URL) throws {
        lock.withLock {
            capturedCreatedDirectories.append(url)
        }
    }

    func copyFile(from sourceURL: URL, to destinationURL: URL) throws {
        lock.withLock {
            capturedCopiedFiles.append(CopiedFile(sourceURL: sourceURL, destinationURL: destinationURL))
        }
    }

    func removeFile(at url: URL) throws {}

    func trashItem(at url: URL) throws {}
}

private actor SpyPassthroughExporter: PassthroughExporter {
    private var capturedRequests: [PassthroughExportRequest] = []

    func export(_ request: PassthroughExportRequest) async throws -> PassthroughExportResult {
        capturedRequests.append(request)
        return PassthroughExportResult(fileURL: request.outputFileURL)
    }

    func requests() -> [PassthroughExportRequest] {
        capturedRequests
    }
}

private struct CopiedFile: Equatable {
    let sourceURL: URL
    let destinationURL: URL
}
