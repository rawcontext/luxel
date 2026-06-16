import Foundation
import LuxelCore
import Testing

@Suite("Bookmarked directory")
struct BookmarkedDirectoryTests {
    @Test("directory stores selected URL bookmark data and access state")
    func directoryStoresSelectedURLBookmarkDataAndAccessState() {
        let directory = BookmarkedDirectory(
            url: URL(fileURLWithPath: "/Users/example/Movies/Luxel"),
            bookmarkData: Data([0x01, 0x02, 0x03])
        )

        #expect(directory.url == URL(fileURLWithPath: "/Users/example/Movies/Luxel"))
        #expect(directory.bookmarkData == Data([0x01, 0x02, 0x03]))
        #expect(directory.accessState == .resolved)
        #expect(!directory.needsRefresh)
    }

    @Test("stale and revoked bookmarks require refresh")
    func staleAndRevokedBookmarksRequireRefresh() {
        let stale = BookmarkedDirectory(
            url: URL(fileURLWithPath: "/tmp/luxel"),
            bookmarkData: Data([0x01]),
            accessState: .stale
        )
        let revoked = BookmarkedDirectory(
            url: URL(fileURLWithPath: "/tmp/luxel"),
            bookmarkData: Data([0x01]),
            accessState: .revoked
        )

        #expect(stale.needsRefresh)
        #expect(revoked.needsRefresh)
    }

    @Test("directory round-trips through codable storage")
    func directoryRoundTripsThroughCodableStorage() throws {
        let directory = BookmarkedDirectory(
            url: URL(fileURLWithPath: "/tmp/luxel"),
            bookmarkData: Data([0xde, 0xad, 0xbe, 0xef]),
            accessState: .stale
        )

        let data = try JSONEncoder().encode(directory)
        let decoded = try JSONDecoder().decode(BookmarkedDirectory.self, from: data)

        #expect(decoded == directory)
    }
}
