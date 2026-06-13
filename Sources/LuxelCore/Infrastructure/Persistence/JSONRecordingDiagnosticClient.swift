import Foundation

public final class JSONRecordingDiagnosticClient: RecordingDiagnosticClient, @unchecked Sendable {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let lock = NSLock()

    public init(fileURL: URL) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
    }

    public func recordCorruptRecording(_ diagnostic: CorruptRecordingDiagnostic) {
        lock.withLock {
            do {
                let directory = fileURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

                var data = try encoder.encode(diagnostic)
                data.append(0x0A)

                if FileManager.default.fileExists(atPath: fileURL.path) {
                    let fileHandle = try FileHandle(forWritingTo: fileURL)
                    defer {
                        try? fileHandle.close()
                    }
                    try fileHandle.seekToEnd()
                    try fileHandle.write(contentsOf: data)
                } else {
                    try data.write(to: fileURL, options: .atomic)
                }
            } catch {
                assertionFailure("Failed to record corrupt recording diagnostic: \(error)")
            }
        }
    }
}
