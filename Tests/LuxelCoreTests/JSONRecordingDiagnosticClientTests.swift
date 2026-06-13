import Foundation
import LuxelCore
import Testing

@Suite("JSON recording diagnostic client")
struct JSONRecordingDiagnosticClientTests {
    @Test("records corrupt recording diagnostics as JSON lines")
    func recordsCorruptRecordingDiagnosticsAsJSONLines() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "luxel-diagnostics-\(UUID().uuidString)", directoryHint: .isDirectory)
        let fileURL = directory.appending(path: "corrupt-recordings.jsonl")
        let client = JSONRecordingDiagnosticClient(fileURL: fileURL)
        let first = CorruptRecordingDiagnostic(
            fileURL: URL(fileURLWithPath: "/tmp/first.mp4"),
            reason: "unexpected decoder failure",
            recordedAt: Date(timeIntervalSince1970: 10)
        )
        let second = CorruptRecordingDiagnostic(
            fileURL: URL(fileURLWithPath: "/tmp/second.mp4"),
            reason: "another failure",
            recordedAt: Date(timeIntervalSince1970: 20)
        )

        client.recordCorruptRecording(first)
        client.recordCorruptRecording(second)

        let lines = try String(contentsOf: fileURL, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let diagnostics = try lines.map { line in
            try decoder.decode(CorruptRecordingDiagnostic.self, from: Data(line.utf8))
        }

        #expect(diagnostics == [first, second])

        try FileManager.default.removeItem(at: directory)
    }
}
