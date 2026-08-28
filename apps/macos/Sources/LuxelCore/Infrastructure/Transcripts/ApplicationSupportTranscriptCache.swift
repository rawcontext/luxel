import Foundation

public final class ApplicationSupportTranscriptCache: TranscriptCache, @unchecked Sendable {
    public static let schemaVersion = 4

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
            localeIdentifier: document.transcript.localeIdentifier,
            speakers: document.transcript.speakers,
            transcriptionProvenance: document.transcript.transcriptionProvenance
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
            request.sourceContext.cacheIdentifier,
            request.turnSegmentationMode.rawValue,
            request.transcriptionProvenance.engine.rawValue,
            request.transcriptionProvenance.modelRevision ?? "",
            request.transcriptionProvenance.configurationRevision ?? "",
            request.speakerDiarizationMode.rawValue,
            request.speakerModelRevision ?? "",
            request.speakerLibraryRevision ?? "",
            request.speakerDiarizationMode == .enabled
                ? request.speakerCountHint.cacheIdentifier : ""
        ].joined(separator: "|")

        return StableFNV1aHash.string(for: rawKey)
    }
}

private struct TranscriptCacheDocument: Codable {
    let schemaVersion: Int
    let transcript: TurnSegmentedTranscript
}
