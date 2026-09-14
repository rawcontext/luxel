import Foundation
import LuxelCore
import Testing

@Suite("Transcript Markdown sidecars")
struct TranscriptMarkdownSidecarTests {
    @Test("transcripts save beside audio and video while retaining the JSON cache", arguments: ["m4a", "mov", "mp4"])
    func savesBothCopies(fileExtension: String) throws {
        let fixture = try Fixture(fileExtension: fileExtension)
        defer { fixture.remove() }
        let transcript = try sampleTestTranscript(text: "Hello *there*", source: .microphone)

        try fixture.cache.save(transcript, for: fixture.request)

        let markdown = try String(contentsOf: fixture.markdownURL, encoding: .utf8)
        #expect(markdown.contains("source_file: \"Meeting.2026.\(fileExtension)\""))
        #expect(markdown.contains("# Meeting.2026\n\n`00:00`\n\nHello \\*there\\*\n"))
        #expect(!markdown.contains("duration_seconds:"))
        #expect(try fixture.cache.load(for: fixture.request) == transcript)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.cacheDirectory.path).count == 1)
        #expect(try Data(contentsOf: fixture.sourceURL) == Data([1, 2, 3]))
    }

    @Test("opening an older cached transcript creates the missing Markdown file")
    func backfillsCachedTranscript() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let transcript = try sampleTestTranscript(text: "Already transcribed", source: nil)
        let oldCache = ApplicationSupportTranscriptCache(cacheDirectory: fixture.cacheDirectory)
        try oldCache.save(transcript, for: fixture.request)
        #expect(!FileManager.default.fileExists(atPath: fixture.markdownURL.path))

        #expect(try fixture.cache.load(for: fixture.request) == transcript)

        #expect(try String(contentsOf: fixture.markdownURL, encoding: .utf8).contains("Already transcribed"))
        try FileManager.default.removeItem(at: fixture.markdownURL)
        #expect(try fixture.cache.load(for: fixture.request) == transcript)
        #expect(FileManager.default.fileExists(atPath: fixture.markdownURL.path))
    }

    @Test("saving an updated transcript refreshes its generated Markdown")
    func updatesGeneratedMarkdown() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try sampleTestTranscript(text: "Original", source: nil)
        let updated = try sampleTestTranscript(text: "Updated", source: nil)

        try fixture.cache.save(original, for: fixture.request)
        try fixture.cache.save(updated, for: fixture.request)

        let markdown = try String(contentsOf: fixture.markdownURL, encoding: .utf8)
        #expect(markdown.contains("Updated"))
        #expect(!markdown.contains("Original"))
        #expect(try fixture.cache.load(for: fixture.request) == updated)
    }

    @Test("existing Markdown is preserved when saving or opening a transcript")
    func preservesUnrelatedMarkdown() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let notes = "# My meeting notes\n"
        try Data(notes.utf8).write(to: fixture.markdownURL)
        let transcript = try sampleTestTranscript(text: "Hello", source: nil)

        try fixture.cache.save(transcript, for: fixture.request)
        #expect(try fixture.cache.load(for: fixture.request) == transcript)

        #expect(try String(contentsOf: fixture.markdownURL, encoding: .utf8) == notes)
    }

    @Test("cache reads leave an existing generated Markdown file unchanged")
    func cacheReadsPreserveMarkdownEdits() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let transcript = try sampleTestTranscript(text: "Hello", source: nil)
        try fixture.cache.save(transcript, for: fixture.request)
        let edited = try String(contentsOf: fixture.markdownURL, encoding: .utf8)
            .replacingOccurrences(of: "Hello", with: "Corrected text")
        try Data(edited.utf8).write(to: fixture.markdownURL)

        #expect(try fixture.cache.load(for: fixture.request) == transcript)

        #expect(try String(contentsOf: fixture.markdownURL, encoding: .utf8) == edited)
    }

    @Test("media with the same base name cannot overwrite each other's Markdown")
    func preservesOtherMediaTranscript() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let audio = try sampleTestTranscript(text: "Audio transcript", source: nil)
        try fixture.cache.save(audio, for: fixture.request)
        let videoURL = fixture.sourceURL.deletingPathExtension().appendingPathExtension("mov")
        try Data([4, 5, 6]).write(to: videoURL)
        let video = try sampleTestTranscript(text: "Video transcript", source: nil)
        let request = AudioTranscriptRequest(audioURL: videoURL)

        try fixture.cache.save(video, for: request)

        #expect(try fixture.cache.load(for: request) == video)
        let markdown = try String(contentsOf: fixture.markdownURL, encoding: .utf8)
        #expect(markdown.contains("Audio transcript"))
        #expect(!markdown.contains("Video transcript"))
    }

    @Test("a Markdown write failure does not discard the internal transcript")
    func retainsCacheOnWriteFailure() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: fixture.markdownURL, withIntermediateDirectories: true)
        let transcript = try sampleTestTranscript(text: "Still available", source: nil)

        try fixture.cache.save(transcript, for: fixture.request)

        #expect(try fixture.cache.load(for: fixture.request) == transcript)
    }

    @Test("saved folder access covers Markdown writes in a resolved recording directory")
    func writesWithBookmarkedDirectoryAccess() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let oldDirectory = fixture.directory.appending(path: "Old Recordings")
        let bookmark = BookmarkedDirectory(url: oldDirectory, bookmarkData: Data([1]))
        let access = SidecarDirectoryAccess()
        let writer = AdjacentMarkdownTranscriptWriter(
            directoryBookmarks: { [bookmark] },
            directoryAccessService: BookmarkedDirectoryAccessService(
                resolver: SidecarDirectoryResolver(url: fixture.sourceURL.deletingLastPathComponent()),
                access: access
            )
        )

        try writer.save(
            sampleTestTranscript(text: "Bookmarked", source: nil),
            sourceURL: oldDirectory.appending(path: fixture.sourceURL.lastPathComponent),
            overwrite: true
        )

        #expect(access.startedURLs == [fixture.sourceURL.deletingLastPathComponent()])
        #expect(access.stoppedURLs == access.startedURLs)
        #expect(try String(contentsOf: fixture.markdownURL, encoding: .utf8).contains("Bookmarked"))
    }

    @Test("revoked folder access retains the cached transcript without writing Markdown")
    func revokedBookmarkRetainsCache() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let bookmark = BookmarkedDirectory(
            url: fixture.sourceURL.deletingLastPathComponent(), bookmarkData: Data([1]))
        let access = SidecarDirectoryAccess()
        let cache = ApplicationSupportTranscriptCache(
            cacheDirectory: fixture.cacheDirectory,
            markdownWriter: AdjacentMarkdownTranscriptWriter(
                directoryBookmarks: { [bookmark] },
                directoryAccessService: BookmarkedDirectoryAccessService(
                    resolver: SidecarDirectoryResolver(url: nil), access: access
                )
            )
        )
        let transcript = try sampleTestTranscript(text: "Cached", source: nil)

        try cache.save(transcript, for: fixture.request)

        #expect(try cache.load(for: fixture.request) == transcript)
        #expect(!FileManager.default.fileExists(atPath: fixture.markdownURL.path))
        #expect(access.startedURLs.isEmpty)
    }
}

private struct Fixture {
    let directory: URL
    let sourceURL: URL
    let cacheDirectory: URL

    init(fileExtension: String = "m4a") throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "LuxelMarkdownTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        sourceURL = directory.appending(path: "Recordings/Meeting.2026.\(fileExtension)")
        cacheDirectory = directory.appending(path: "Application Support/Transcripts")
        try FileManager.default.createDirectory(
            at: sourceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: sourceURL)
    }

    var request: AudioTranscriptRequest { AudioTranscriptRequest(audioURL: sourceURL) }
    var markdownURL: URL { sourceURL.deletingPathExtension().appendingPathExtension("md") }
    var cache: ApplicationSupportTranscriptCache {
        ApplicationSupportTranscriptCache(
            cacheDirectory: cacheDirectory,
            markdownWriter: AdjacentMarkdownTranscriptWriter()
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private struct SidecarDirectoryResolver: BookmarkedDirectoryResolver {
    let url: URL?

    func resolve(_ directory: BookmarkedDirectory) throws -> BookmarkedDirectoryResolution {
        guard let url else { throw CocoaError(.fileReadNoPermission) }
        return BookmarkedDirectoryResolution(url: url, bookmarkData: directory.bookmarkData, isStale: false)
    }
}

private final class SidecarDirectoryAccess: SecurityScopedResourceAccess, @unchecked Sendable {
    private(set) var startedURLs: [URL] = []
    private(set) var stoppedURLs: [URL] = []

    func startAccessing(_ url: URL) -> Bool {
        startedURLs.append(url)
        return true
    }

    func stopAccessing(_ url: URL) {
        stoppedURLs.append(url)
    }
}
