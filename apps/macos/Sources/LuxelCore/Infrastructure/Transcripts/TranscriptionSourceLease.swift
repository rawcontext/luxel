import Foundation

struct TranscriptionSourceLease {
    let url: URL
    private let temporary: Bool

    init(sourceURL: URL, temporaryDirectory: URL) throws {
        temporary = RecordingDocumentStore.identifier(for: sourceURL) != nil
        guard temporary else {
            url = sourceURL
            return
        }
        url = temporaryDirectory.appending(path: "LuxelSpeech-\(UUID().uuidString)")
            .appendingPathExtension(sourceURL.pathExtension)
        do {
            try FileManager.default.linkItem(at: sourceURL, to: url)
        } catch {
            try FileManager.default.copyItem(at: sourceURL, to: url)
        }
    }

    func release() {
        if temporary { try? FileManager.default.removeItem(at: url) }
    }
}
