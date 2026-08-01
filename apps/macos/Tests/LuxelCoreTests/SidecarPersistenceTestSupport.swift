import Foundation
import LuxelCore
import Testing

func expectSavedSidecar<Document: Decodable & Equatable>(
    _ type: Document.Type,
    expectedDocument: Document,
    fileSystem: SidecarTestFileSystem,
    updatedBundle: RecordingBundle
) throws {
    let document = try JSONDecoder().decode(
        type,
        from: try #require(fileSystem.writtenData.first?.data)
    )
    #expect(document == expectedDocument)
    let manifest = try JSONDecoder().decode(
        BundleManifest.self,
        from: try #require(fileSystem.writtenData.last?.data)
    )
    #expect(manifest == updatedBundle.manifest)
}

func expectWrittenSidecar(
    named fileName: String,
    rootURL: URL,
    fileSystem: SidecarTestFileSystem
) {
    #expect(fileSystem.writtenData.map(\.url) == [rootURL.appendingPathComponent(fileName)])
}

final class SidecarTestFileSystem: FileSystem, @unchecked Sendable {
    private let dataByURL: [URL: Data]
    private(set) var readURLs: [URL] = []
    private(set) var writtenData: [SidecarWrittenData] = []

    init(readData: [URL: Data] = [:]) {
        self.dataByURL = readData
    }

    func fileExists(at url: URL) -> Bool { true }
    func createDirectory(at url: URL) throws {}
    func copyFile(from sourceURL: URL, to destinationURL: URL) throws {}

    func readData(at url: URL) throws -> Data {
        readURLs.append(url)
        guard let data = dataByURL[url] else {
            throw FileSystemError.unsupportedRead(url)
        }
        return data
    }

    func writeData(_ data: Data, to url: URL) throws {
        writtenData.append(SidecarWrittenData(data: data, url: url))
    }

    func removeFile(at url: URL) throws {}
    func trashItem(at url: URL) throws {}
}

struct SidecarWrittenData: Equatable {
    let data: Data
    let url: URL
}
