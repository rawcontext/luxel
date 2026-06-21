import Foundation

public final class JSONRecordingHistoryStore: RecordingHistoryStore, @unchecked Sendable {
    private struct Snapshot: Codable {
        var activeRecording: ActiveRecording?
        var recordings: [PastRecording]

        init(activeRecording: ActiveRecording?, recordings: [PastRecording]) {
            self.activeRecording = activeRecording
            self.recordings = recordings
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            activeRecording = try container.decodeIfPresent(
                ActiveRecording.self, forKey: .activeRecording)
            recordings =
                try container.decodeIfPresent([LossyPastRecording].self, forKey: .recordings)?
                .compactMap(\.value) ?? []
        }
    }

    private struct LossyPastRecording: Decodable {
        let value: PastRecording?

        init(from decoder: any Decoder) throws {
            value = try? PastRecording(from: decoder)
        }
    }

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var snapshot: Snapshot

    public var activeRecording: ActiveRecording? {
        get { snapshot.activeRecording }
        set {
            snapshot.activeRecording = newValue
            persist()
        }
    }

    public var recordings: [PastRecording] {
        get { snapshot.recordings }
        set {
            snapshot.recordings = newValue
            persist()
        }
    }

    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601

        if FileManager.default.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            self.snapshot = try decoder.decode(Snapshot.self, from: data)
        } else {
            self.snapshot = Snapshot(activeRecording: nil, recordings: [])
            persist()
        }
    }

    private func persist() {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            assertionFailure("Failed to persist recording history: \(error)")
        }
    }
}
