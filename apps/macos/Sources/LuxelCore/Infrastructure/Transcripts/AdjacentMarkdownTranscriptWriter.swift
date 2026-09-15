import Foundation

public struct AdjacentMarkdownTranscriptWriter: Sendable {
    private let directoryBookmarks: @Sendable () -> [BookmarkedDirectory]
    private let directoryAccessService: BookmarkedDirectoryAccessService

    public init(
        directoryBookmarks: @escaping @Sendable () -> [BookmarkedDirectory] = { [] },
        directoryAccessService: BookmarkedDirectoryAccessService = BookmarkedDirectoryAccessService(
            resolver: FoundationBookmarkedDirectoryResolver(),
            access: URLSecurityScopedResourceAccess()
        )
    ) {
        self.directoryBookmarks = directoryBookmarks
        self.directoryAccessService = directoryAccessService
    }

    public func save(
        _ transcript: TurnSegmentedTranscript,
        sourceURL: URL,
        overwrite: Bool
    ) throws {
        let sourcePath = sourceURL.standardizedFileURL.path
        let bookmark = directoryBookmarks().first {
            sourcePath.hasPrefix($0.url.standardizedFileURL.path + "/")
        }
        guard let bookmark else {
            try write(transcript, sourceURL: sourceURL, overwrite: overwrite)
            return
        }

        let result = try directoryAccessService.withAccess(to: bookmark) { directory in
            let relativePath = String(sourcePath.dropFirst(bookmark.url.standardizedFileURL.path.count + 1))
            try write(
                transcript,
                sourceURL: directory.url.appending(path: relativePath),
                overwrite: overwrite
            )
        }
        guard result.value != nil else {
            throw CocoaError(.fileWriteNoPermission)
        }
    }

    private func write(
        _ transcript: TurnSegmentedTranscript,
        sourceURL: URL,
        overwrite: Bool
    ) throws {
        let outputURL = sourceURL.deletingPathExtension().appendingPathExtension("md")
        let marker = Self.ownershipMarker(for: sourceURL)
        let exists = FileManager.default.fileExists(atPath: outputURL.path)
        if exists {
            guard overwrite,
                try String(contentsOf: outputURL, encoding: .utf8).hasSuffix(marker)
            else {
                return
            }
        }

        let markdown =
            TranscriptCopyTextBuilder().text(
                transcript: transcript,
                visibleWords: [],
                hasCuts: false,
                metadata: TranscriptMarkdownMetadata(
                    sourceURL: sourceURL,
                    duration: (try? RecordingDocumentStore().load(nextTo: sourceURL))?.manifest.organization?.duration
                ),
                includesTimestamps: true
            ) + marker
        try Data(markdown.utf8).write(
            to: outputURL,
            options: exists ? .atomic : .withoutOverwriting
        )
        _ = try? RecordingDocumentStore().update(nextTo: sourceURL) {
            $0.transcriptFileName = outputURL.lastPathComponent
        }
    }

    static func ownershipMarker(for sourceURL: URL) -> String {
        let identifier = Data(sourceURL.lastPathComponent.utf8).base64EncodedString()
        return "\n<!-- luxel-transcript-source: \(identifier) -->\n"
    }
}
