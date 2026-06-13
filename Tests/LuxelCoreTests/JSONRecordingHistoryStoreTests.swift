import Foundation
import LuxelCore
import Testing

@Suite("JSON recording history store")
struct JSONRecordingHistoryStoreTests {
    @Test("persists active recording and past recordings")
    func persistsHistorySnapshot() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appending(path: "recording-history.json")
        let fileURL = directory.appending(path: "recording.mp4")
        let active = ActiveRecording(
            fileURL: fileURL,
            name: "Luxel 2020-07-21 at 11.27.26",
            date: Date(timeIntervalSince1970: 100),
            options: RecordingOptions(frameRate: 60, showCursor: true, highlightClicks: true)
        )
        let past = PastRecording(
            fileURL: fileURL,
            name: "Finished",
            date: Date(timeIntervalSince1970: 200)
        )

        let writer = try JSONRecordingHistoryStore(fileURL: storeURL)
        writer.activeRecording = active
        writer.recordings = [past]

        let reader = try JSONRecordingHistoryStore(fileURL: storeURL)
        #expect(reader.activeRecording == active)
        #expect(reader.recordings == [past])
    }

    @Test("loads legacy past recordings without options")
    func loadsLegacyPastRecordingsWithoutOptions() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appending(path: "recording-history.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("""
        {
          "activeRecording": null,
          "recordings": [
            {
              "date": "1970-01-01T00:00:01Z",
              "fileURL": "file:///tmp/legacy.mp4",
              "name": "Legacy"
            }
          ]
        }
        """.utf8).write(to: storeURL)

        let store = try JSONRecordingHistoryStore(fileURL: storeURL)

        #expect(store.recordings == [
            PastRecording(
                fileURL: URL(fileURLWithPath: "/tmp/legacy.mp4"),
                name: "Legacy",
                date: Date(timeIntervalSince1970: 1)
            )
        ])
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appending(path: "luxel-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }
}
