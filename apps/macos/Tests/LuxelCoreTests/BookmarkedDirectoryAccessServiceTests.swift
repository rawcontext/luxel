import Foundation
import LuxelCore
import Testing

@Suite("Bookmarked directory access service")
struct BookmarkedDirectoryAccessServiceTests {
    @Test("resolve marks fresh bookmarks resolved")
    func resolveMarksFreshBookmarksResolved() {
        let directory = makeDirectory()
        let resolver = StubBookmarkedDirectoryResolver(
            resolution: BookmarkedDirectoryResolution(
                url: URL(fileURLWithPath: "/tmp/resolved"),
                bookmarkData: Data([0x02]),
                isStale: false
            )
        )
        let service = BookmarkedDirectoryAccessService(
            resolver: resolver,
            access: SpySecurityScopedResourceAccess()
        )

        let resolved = service.resolve(directory)

        #expect(
            resolved
                == BookmarkedDirectory(
                    url: URL(fileURLWithPath: "/tmp/resolved"),
                    bookmarkData: Data([0x02]),
                    accessState: .resolved
                ))
    }

    @Test("resolve marks stale bookmarks stale")
    func resolveMarksStaleBookmarksStale() {
        let directory = makeDirectory()
        let resolver = StubBookmarkedDirectoryResolver(
            resolution: BookmarkedDirectoryResolution(
                url: directory.url,
                bookmarkData: directory.bookmarkData,
                isStale: true
            )
        )
        let service = BookmarkedDirectoryAccessService(
            resolver: resolver,
            access: SpySecurityScopedResourceAccess()
        )

        let resolved = service.resolve(directory)

        #expect(resolved.accessState == .stale)
        #expect(resolved.needsRefresh)
    }

    @Test("resolve marks failed bookmarks revoked")
    func resolveMarksFailedBookmarksRevoked() {
        let directory = makeDirectory()
        let service = BookmarkedDirectoryAccessService(
            resolver: StubBookmarkedDirectoryResolver(error: StubError.revoked),
            access: SpySecurityScopedResourceAccess()
        )

        let resolved = service.resolve(directory)

        #expect(
            resolved
                == BookmarkedDirectory(
                    url: directory.url,
                    bookmarkData: directory.bookmarkData,
                    accessState: .revoked
                ))
    }

    @Test("with access balances successful security scope")
    func withAccessBalancesSuccessfulSecurityScope() {
        let context = makeAccessContext()

        let result = context.service.withAccess(to: context.directory) { resolvedDirectory in
            #expect(context.access.activeURLs == [resolvedDirectory.url])
            return resolvedDirectory.url.lastPathComponent
        }

        expectBalancedAccess(result: result, context: context)
    }

    @Test("async with access balances successful security scope")
    func asyncWithAccessBalancesSuccessfulSecurityScope() async {
        let context = makeAccessContext()

        let result = await context.service.withAccess(to: context.directory) { resolvedDirectory in
            #expect(context.access.activeURLs == [resolvedDirectory.url])
            await Task.yield()
            return resolvedDirectory.url.lastPathComponent
        }

        expectBalancedAccess(result: result, context: context)
    }

    @Test("with access does not stop when security scope does not start")
    func withAccessDoesNotStopWhenSecurityScopeDoesNotStart() {
        let directory = makeDirectory()
        let access = SpySecurityScopedResourceAccess(startsSuccessfully: false)
        let service = BookmarkedDirectoryAccessService(
            resolver: StubBookmarkedDirectoryResolver(
                resolution: BookmarkedDirectoryResolution(
                    url: directory.url,
                    bookmarkData: directory.bookmarkData,
                    isStale: false
                )
            ),
            access: access
        )

        let result = service.withAccess(to: directory) { _ in "fallback" }

        #expect(result.value == "fallback")
        #expect(!result.accessStarted)
        #expect(access.startedURLs == [directory.url])
        #expect(access.stoppedURLs.isEmpty)
    }

    @Test("with access skips operation when bookmark is revoked")
    func withAccessSkipsOperationWhenBookmarkIsRevoked() {
        let directory = makeDirectory()
        let access = SpySecurityScopedResourceAccess()
        let service = BookmarkedDirectoryAccessService(
            resolver: StubBookmarkedDirectoryResolver(error: StubError.revoked),
            access: access
        )

        let result = service.withAccess(to: directory) { _ in
            Issue.record("Revoked bookmarks should not run protected operations")
            return "unreachable"
        }

        #expect(result.value == nil)
        #expect(result.directory.accessState == .revoked)
        #expect(!result.accessStarted)
        #expect(access.startedURLs.isEmpty)
        #expect(access.stoppedURLs.isEmpty)
    }

    private func makeDirectory() -> BookmarkedDirectory {
        BookmarkedDirectory(
            url: URL(fileURLWithPath: "/tmp/selected"),
            bookmarkData: Data([0x01]),
            accessState: .resolved
        )
    }

    private func makeAccessContext() -> BookmarkedAccessContext {
        let directory = makeDirectory()
        let access = SpySecurityScopedResourceAccess()
        let service = BookmarkedDirectoryAccessService(
            resolver: StubBookmarkedDirectoryResolver(
                resolution: BookmarkedDirectoryResolution(
                    url: directory.url,
                    bookmarkData: directory.bookmarkData,
                    isStale: false
                )
            ),
            access: access
        )
        return BookmarkedAccessContext(directory: directory, access: access, service: service)
    }

    private func expectBalancedAccess(
        result: BookmarkedDirectoryAccessResult<String>,
        context: BookmarkedAccessContext
    ) {
        #expect(result.value == "selected")
        #expect(result.accessStarted)
        #expect(context.access.startedURLs == [context.directory.url])
        #expect(context.access.stoppedURLs == [context.directory.url])
        #expect(context.access.activeURLs.isEmpty)
    }
}

private struct BookmarkedAccessContext {
    let directory: BookmarkedDirectory
    let access: SpySecurityScopedResourceAccess
    let service: BookmarkedDirectoryAccessService
}

private struct StubBookmarkedDirectoryResolver: BookmarkedDirectoryResolver {
    let resolution: BookmarkedDirectoryResolution?
    let error: (any Error)?

    init(resolution: BookmarkedDirectoryResolution? = nil, error: (any Error)? = nil) {
        self.resolution = resolution
        self.error = error
    }

    func resolve(_ directory: BookmarkedDirectory) throws -> BookmarkedDirectoryResolution {
        if let error {
            throw error
        }

        return resolution
            ?? BookmarkedDirectoryResolution(
                url: directory.url,
                bookmarkData: directory.bookmarkData,
                isStale: false
            )
    }
}

private final class SpySecurityScopedResourceAccess: SecurityScopedResourceAccess,
    @unchecked Sendable
{
    private let startsSuccessfully: Bool
    private(set) var startedURLs: [URL] = []
    private(set) var stoppedURLs: [URL] = []
    private(set) var activeURLs: [URL] = []

    init(startsSuccessfully: Bool = true) {
        self.startsSuccessfully = startsSuccessfully
    }

    func startAccessing(_ url: URL) -> Bool {
        startedURLs.append(url)

        guard startsSuccessfully else {
            return false
        }

        activeURLs.append(url)
        return true
    }

    func stopAccessing(_ url: URL) {
        stoppedURLs.append(url)
        activeURLs.removeAll { $0 == url }
    }
}

private enum StubError: Error {
    case revoked
}
