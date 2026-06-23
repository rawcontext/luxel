import Foundation

public final class ApplicationSupportTranscriptCache: TranscriptCache, @unchecked Sendable {
    public static let schemaVersion = 1

    private let cacheDirectory: URL
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        cacheDirectory: URL,
        fileManager: FileManager = .default
    ) {
        self.cacheDirectory = cacheDirectory
        self.fileManager = fileManager
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
    }

    public func load(for request: AudioTranscriptRequest) throws -> TurnSegmentedTranscript? {
        let fileURL = try cacheFileURL(for: request)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        let document = try decoder.decode(TranscriptCacheDocument.self, from: data)
        guard document.schemaVersion == Self.schemaVersion else {
            return nil
        }

        return try TurnSegmentedTranscript(
            spans: document.transcript.spans,
            turns: document.transcript.turns,
            localeIdentifier: document.transcript.localeIdentifier
        )
    }

    public func save(_ transcript: TurnSegmentedTranscript, for request: AudioTranscriptRequest)
    throws {
        let fileURL = try cacheFileURL(for: request)
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let document = TranscriptCacheDocument(
            schemaVersion: Self.schemaVersion,
            transcript: transcript
        )
        let data = try encoder.encode(document)
        try data.write(to: fileURL, options: .atomic)
    }

    private func cacheFileURL(for request: AudioTranscriptRequest) throws -> URL {
        try cacheDirectory.appending(path: "\(cacheKey(for: request)).json")
    }

    private func cacheKey(for request: AudioTranscriptRequest) throws -> String {
        let attributes = try fileManager.attributesOfItem(atPath: request.audioURL.path)
        let size = attributes[.size] as? NSNumber
        let modificationDate = attributes[.modificationDate] as? Date
        let rawKey = [
            "v\(Self.schemaVersion)",
            request.audioURL.standardizedFileURL.path,
            "\(size?.int64Value ?? 0)",
            "\(modificationDate?.timeIntervalSince1970 ?? 0)",
            request.locale.identifier,
            request.sourceContext.cacheIdentifier
        ].joined(separator: "|")

        return stableFNV1aHash(rawKey)
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

private struct TranscriptCacheDocument: Codable {
    let schemaVersion: Int
    let transcript: TurnSegmentedTranscript
}
