import Foundation
import LuxelCore
import Testing

@Suite("Foundation bookmarked directory adapters")
struct BookmarkedDirectoryAdaptersTests {
    @Test("creator stores a security scoped bookmark for the selected directory")
    func creatorStoresSecurityScopedBookmark() throws {
        let directoryURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let directory = try FoundationBookmarkCreator()
            .bookmarkDirectory(at: directoryURL)

        #expect(directory.url == directoryURL)
        #expect(!directory.bookmarkData.isEmpty)
        #expect(directory.accessState == .resolved)
    }

    @Test("resolver resolves bookmark data through Foundation")
    func resolverResolvesBookmarkData() throws {
        let directoryURL = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let directory = try FoundationBookmarkCreator()
            .bookmarkDirectory(at: directoryURL)

        let resolution = try FoundationBookmarkedDirectoryResolver()
            .resolve(directory)

        #expect(resolution.url.standardizedFileURL == directoryURL.standardizedFileURL)
        #expect(resolution.bookmarkData == directory.bookmarkData)
        #expect(!resolution.isStale)
    }

    private func temporaryDirectory() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "luxel-bookmark-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL
    }
}
