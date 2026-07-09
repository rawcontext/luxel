import Foundation

public final class SpeakerDiarizationArtifactsFileStore:
    SpeakerDiarizationArtifactsStore, @unchecked Sendable {
    public static let schemaVersion = 1

    private let directory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
    }

    public func load(audioURL: URL) throws -> SpeakerDiarizationArtifacts? {
        let fileURL = try fileURL(for: audioURL)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let document = try decoder.decode(
            ArtifactsDocument.self,
            from: Data(contentsOf: fileURL)
        )
        guard document.schemaVersion == Self.schemaVersion else {
            return nil
        }

        return document.artifacts
    }

    public func save(_ artifacts: SpeakerDiarizationArtifacts, audioURL: URL) throws {
        let fileURL = try fileURL(for: audioURL)
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let document = ArtifactsDocument(
            schemaVersion: Self.schemaVersion,
            artifacts: artifacts
        )
        try encoder.encode(document).write(to: fileURL, options: .atomic)
    }

    private func fileURL(for audioURL: URL) throws -> URL {
        let attributes = try fileManager.attributesOfItem(atPath: audioURL.path)
        let size = attributes[.size] as? NSNumber
        let modificationDate = attributes[.modificationDate] as? Date
        let rawKey = [
            "v\(Self.schemaVersion)",
            audioURL.standardizedFileURL.path,
            "\(size?.int64Value ?? 0)",
            "\(modificationDate?.timeIntervalSince1970 ?? 0)"
        ].joined(separator: "|")

        return directory.appending(path: "\(stableFNV1aHash(rawKey)).json")
    }

    private func stableFNV1aHash(_ string: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }

        return String(hash, radix: 16)
    }
}

private struct ArtifactsDocument: Codable {
    let schemaVersion: Int
    let artifacts: SpeakerDiarizationArtifacts
}
