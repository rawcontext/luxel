import Foundation
import LuxelCore
import Testing

@Suite("Recording organization")
struct RecordingOrganizationTests {
    @Test("new media uses month and session folders with matching stems")
    func chronologicalLayout() throws {
        let root = URL(fileURLWithPath: "/recordings")
        let date = try #require(ISO8601DateFormatter().date(from: "2026-09-14T14:32:08Z"))
        for ext in ["mp4", "m4a", "webm"] {
            let url = RecordingFileLayout.mediaURL(
                in: root, date: date, title: "Checkout / validation: bug", fileExtension: ext,
                timeZone: .gmt, exists: { _ in false })
            let stem = "2026-09-14 14.32.08 - Checkout validation bug"
            #expect(url.path == "/recordings/2026-09/\(stem)/\(stem).\(ext)")
        }
        let collision = RecordingFileLayout.mediaURL(
            in: root, date: date, title: "Checkout", fileExtension: "mp4", timeZone: .gmt,
            exists: { !$0.lastPathComponent.hasSuffix("(2)") })
        #expect(collision.lastPathComponent == "2026-09-14 14.32.08 - Checkout (2).mp4")
    }

    @Test("existing loose recordings stay in place without new folders or manifests")
    func existingFilesAreUntouched() throws {
        let fixture = try OrganizedRecordingFixture()
        defer { fixture.remove() }
        let loose = fixture.root.appending(path: "My existing recording.mp4")
        try Data([9]).write(to: loose)
        let old = PastRecording(fileURL: loose, name: "My existing recording", date: fixture.date)
        let result = try RecordingDocumentStore().create(for: old, captureKind: "screen")
        #expect(result == old)
        #expect(try Data(contentsOf: loose) == Data([9]))
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appending(path: "bundle.json").path))
    }

    @Test("automatic naming preserves identity, cached text and matching Markdown")
    func automaticRenamePreservesAssociations() throws {
        let fixture = try OrganizedRecordingFixture()
        defer { fixture.remove() }
        let recording = try fixture.organized()
        let transcript = try sampleTestTranscript(text: "Checkout validation failed", source: nil)
        let request = AudioTranscriptRequest(audioURL: recording.primaryMediaURL)
        try fixture.cache.save(transcript, for: request)
        let updated = try RecordingDocumentStore().applyingAutomaticTitle(
            "Checkout validation bug", to: recording, transcript: transcript)

        #expect(updated.bundleManifest?.organization?.id == recording.bundleManifest?.organization?.id)
        #expect(updated.bundleManifest?.organization?.titleOrigin == .intelligence)
        #expect(updated.bundleManifest?.organization?.pathsLocked == true)
        #expect(
            updated.primaryMediaURL.deletingLastPathComponent().lastPathComponent
                == updated.primaryMediaURL.deletingPathExtension().lastPathComponent)
        #expect(try Data(contentsOf: updated.primaryMediaURL) == Data([1, 2, 3]))
        #expect(!FileManager.default.fileExists(atPath: recording.primaryMediaURL.path))
        #expect(try fixture.cache.load(for: AudioTranscriptRequest(audioURL: updated.primaryMediaURL)) == transcript)
        let markdown = updated.primaryMediaURL.deletingPathExtension().appendingPathExtension("md")
        #expect(try String(contentsOf: markdown, encoding: .utf8).contains("Checkout validation bug"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.cacheDirectory.path).count == 1)
    }

    @Test("opening or exporting locks filenames against delayed title generation")
    func lockedPathsDoNotRename() throws {
        let fixture = try OrganizedRecordingFixture()
        defer { fixture.remove() }
        let recording = try fixture.organized()
        try RecordingDocumentStore().lockPaths(nextTo: recording.primaryMediaURL)
        let result = try RecordingDocumentStore().applyingAutomaticTitle(
            "Delayed title", to: recording,
            transcript: sampleTestTranscript(text: "Hello", source: nil))
        #expect(result.fileURL == recording.fileURL)
        #expect(FileManager.default.fileExists(atPath: recording.primaryMediaURL.path))
    }

    @Test("portable identity, favorites, edit state and export paths survive moving a session")
    func movingSessionPreservesMetadata() throws {
        let fixture = try OrganizedRecordingFixture()
        defer { fixture.remove() }
        let recording = try fixture.organized()
        let documents = RecordingDocumentStore()
        let exports = try #require(RecordingDocumentStore.exportsDirectory(for: recording.primaryMediaURL))
        #expect(!FileManager.default.fileExists(atPath: exports.path))
        try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
        let exported = exports.appending(path: "Web.mp4")
        try Data([4]).write(to: exported)
        try documents.recordExport(
            RecordingExport(fileURL: exported, format: .mp4, date: fixture.date), sourceURL: recording.primaryMediaURL)
        _ = try documents.update(nextTo: recording.primaryMediaURL) {
            $0.isFavorite = true
            $0.editState = RecordingEditState(trimStart: 1, trimEnd: 2, transcriptEditPlan: .empty)
        }
        let movedRoot = fixture.root.appending(path: "Moved session")
        try FileManager.default.moveItem(at: recording.primaryMediaURL.deletingLastPathComponent(), to: movedRoot)
        let moved = movedRoot.appending(path: recording.primaryMediaURL.lastPathComponent)
        let manifest = try #require(try documents.load(nextTo: moved)?.manifest)
        #expect(manifest.organization?.id == recording.bundleManifest?.organization?.id)
        #expect(manifest.organization?.isFavorite == true)
        #expect(manifest.organization?.editState?.trimStart == 1)
        #expect(manifest.organization?.exports.first?.relativePath == "Exports/Web.mp4")
        #expect(FileManager.default.fileExists(atPath: movedRoot.appending(path: "Exports/Web.mp4").path))
        #expect(
            documents.recordings(in: fixture.root).map { $0.primaryMediaURL.resolvingSymlinksInPath() }
                == [moved.resolvingSymlinksInPath()])
    }

    @Test("new audio manifests retain capture options and source application")
    func metadataRoundTrip() throws {
        let fixture = try OrganizedRecordingFixture(fileExtension: "m4a")
        defer { fixture.remove() }
        let recording = try fixture.organized()
        let document = try #require(try RecordingDocumentStore().load(nextTo: recording.primaryMediaURL))
        #expect(document.manifest.organization?.captureKind == "audio")
        #expect(document.manifest.organization?.sourceApplication == "Safari")
        #expect(document.manifest.organization?.recordingOptions?.isAudioOnly == true)
        #expect(document.manifest.organization?.capturedAt == fixture.date)
    }
}

struct OrganizedRecordingFixture {
    let root: URL
    let sourceURL: URL
    let date = Date(timeIntervalSince1970: 1_789_397_928)
    let isAudio: Bool

    init(fileExtension: String = "mp4") throws {
        root = FileManager.default.temporaryDirectory.appending(path: "LuxelOrganization-\(UUID().uuidString)")
        isAudio = fileExtension == "m4a"
        sourceURL = RecordingFileLayout.mediaURL(
            in: root, date: date, title: "Screen recording", fileExtension: fileExtension)
        try FileManager.default.createDirectory(
            at: sourceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: sourceURL)
    }

    var cacheDirectory: URL { root.appending(path: "Cache") }
    var cache: ApplicationSupportTranscriptCache {
        ApplicationSupportTranscriptCache(
            cacheDirectory: cacheDirectory, markdownWriter: AdjacentMarkdownTranscriptWriter())
    }

    func organized() throws -> PastRecording {
        try RecordingDocumentStore().create(
            for: PastRecording(
                fileURL: sourceURL, name: sourceURL.deletingPathExtension().lastPathComponent,
                date: date, options: RecordingOptions(frameRate: 30, isAudioOnly: isAudio)),
            captureKind: isAudio ? "audio" : "screen", sourceApplication: "Safari")
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}
