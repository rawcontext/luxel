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

    @Test("trimmed passthrough is explicit future work")
    func trimmedPassthroughIsExplicitFutureWork() async throws {
        let service = PassthroughExportService(fileSystem: LocalFileSystem())
        let request = try PassthroughExportRequest(
            inputFileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            outputFileURL: URL(fileURLWithPath: "/tmp/output.mp4"),
            timeRange: TimeRange(start: 1, end: 2)
        )

        await #expect(throws: PassthroughExportError.trimmedPassthroughNotImplemented) {
            _ = try await service.export(request)
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "luxel-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}
