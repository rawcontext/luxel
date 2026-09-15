import Foundation
import LuxelCore
import Testing

@Suite("Recording organization safety")
struct RecordingOrganizationSafetyTests {
    @Test("a user rename keeps the transcript, identity and Markdown metadata together")
    func userRename() throws {
        let fixture = try OrganizedRecordingFixture()
        defer { fixture.remove() }
        let recording = try fixture.organized()
        let transcript = try sampleTestTranscript(text: "Meeting notes", source: nil)
        try fixture.cache.save(transcript, for: AudioTranscriptRequest(audioURL: fixture.sourceURL))
        let destination = fixture.sourceURL.deletingLastPathComponent().appending(path: "User chosen title.mp4")
        try FileManager.default.moveItem(at: fixture.sourceURL, to: destination)
        let manifest = try #require(
            try RecordingDocumentStore().synchronizeUserRename(from: fixture.sourceURL, to: destination))
        #expect(manifest.organization?.id == recording.bundleManifest?.organization?.id)
        #expect(manifest.organization?.titleOrigin == .user)
        #expect(manifest.organization?.pathsLocked == true)
        #expect(try fixture.cache.load(for: AudioTranscriptRequest(audioURL: destination)) == transcript)
        let markdown = try String(
            contentsOf: destination.deletingPathExtension().appendingPathExtension("md"), encoding: .utf8)
        #expect(markdown.contains("source_file: \"User chosen title.mp4\""))
        #expect(markdown.contains("# User chosen title"))
    }

    @Test("automatic naming preserves unrelated notes in the recording directory")
    func preservesUnrelatedNotes() throws {
        let fixture = try OrganizedRecordingFixture()
        defer { fixture.remove() }
        let recording = try fixture.organized()
        let note = fixture.sourceURL.deletingPathExtension().appendingPathExtension("md")
        try Data("Personal notes".utf8).write(to: note)
        let updated = try RecordingDocumentStore().applyingAutomaticTitle(
            "New recording title", to: recording, transcript: sampleTestTranscript(text: "Hello", source: nil))
        let preserved = updated.primaryMediaURL.deletingLastPathComponent().appending(path: note.lastPathComponent)
        #expect(try String(contentsOf: preserved, encoding: .utf8) == "Personal notes")
        #expect(updated.bundleManifest?.organization?.transcriptFileName != note.lastPathComponent)
    }

    @Test("a Markdown collision rolls back automatic media renaming")
    func automaticRenameCollision() throws {
        let fixture = try OrganizedRecordingFixture()
        defer { fixture.remove() }
        let recording = try fixture.organized()
        let transcript = try sampleTestTranscript(text: "Hello", source: nil)
        try fixture.cache.save(transcript, for: AudioTranscriptRequest(audioURL: fixture.sourceURL))
        let newStem = RecordingFileLayout.stem(title: "New title", date: fixture.date)
        let notes = fixture.sourceURL.deletingLastPathComponent().appending(path: newStem).appendingPathExtension("md")
        try Data("Preserve this".utf8).write(to: notes)

        #expect(throws: (any Error).self) {
            try RecordingDocumentStore().applyingAutomaticTitle("New title", to: recording, transcript: transcript)
        }

        #expect(try String(contentsOf: notes, encoding: .utf8) == "Preserve this")
        #expect(try Data(contentsOf: fixture.sourceURL) == Data([1, 2, 3]))
        #expect(try fixture.cache.load(for: AudioTranscriptRequest(audioURL: fixture.sourceURL)) == transcript)
    }

    @Test("concurrent transcript metadata updates do not lose path locks or favorites")
    func concurrentMetadataUpdates() async throws {
        let fixture = try OrganizedRecordingFixture()
        defer { fixture.remove() }
        _ = try fixture.organized()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<30 {
                group.addTask {
                    _ = try RecordingDocumentStore().update(nextTo: fixture.sourceURL) {
                        if index == 0 {
                            $0.pathsLocked = true
                        } else if index == 1 {
                            $0.isFavorite = true
                        } else {
                            $0.duration = Double(index)
                        }
                    }
                }
            }
            try await group.waitForAll()
        }
        let document = try #require(try RecordingDocumentStore().load(nextTo: fixture.sourceURL))
        #expect(document.manifest.organization?.pathsLocked == true)
        #expect(document.manifest.organization?.isFavorite == true)
    }
}
