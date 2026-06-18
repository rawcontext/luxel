import Foundation

public struct BookmarkedDirectoryAccessService: Sendable {
    private let resolver: any BookmarkedDirectoryResolver
    private let access: any SecurityScopedResourceAccess

    public init(
        resolver: any BookmarkedDirectoryResolver,
        access: any SecurityScopedResourceAccess
    ) {
        self.resolver = resolver
        self.access = access
    }

    public func resolve(_ directory: BookmarkedDirectory) -> BookmarkedDirectory {
        do {
            let resolution = try resolver.resolve(directory)
            return BookmarkedDirectory(
                url: resolution.url,
                bookmarkData: resolution.bookmarkData,
                accessState: resolution.isStale ? .stale : .resolved
            )
        } catch {
            return BookmarkedDirectory(
                url: directory.url,
                bookmarkData: directory.bookmarkData,
                accessState: .revoked
            )
        }
    }

    public func withAccess<Result>(
        to directory: BookmarkedDirectory,
        operation: (BookmarkedDirectory) throws -> Result
    ) rethrows -> BookmarkedDirectoryAccessResult<Result> {
        let resolvedDirectory = resolve(directory)

        guard resolvedDirectory.accessState != .revoked else {
            return BookmarkedDirectoryAccessResult(
                directory: resolvedDirectory,
                value: nil,
                accessStarted: false
            )
        }

        let accessStarted = access.startAccessing(resolvedDirectory.url)
        defer {
            if accessStarted {
                access.stopAccessing(resolvedDirectory.url)
            }
        }

        return BookmarkedDirectoryAccessResult(
            directory: resolvedDirectory,
            value: try operation(resolvedDirectory),
            accessStarted: accessStarted
        )
    }

    public func withAccess<Result>(
        to directory: BookmarkedDirectory,
        operation: @Sendable (BookmarkedDirectory) async throws -> Result
    ) async rethrows -> BookmarkedDirectoryAccessResult<Result> {
        let resolvedDirectory = resolve(directory)

        guard resolvedDirectory.accessState != .revoked else {
            return BookmarkedDirectoryAccessResult(
                directory: resolvedDirectory,
                value: nil,
                accessStarted: false
            )
        }

        let accessStarted = access.startAccessing(resolvedDirectory.url)
        defer {
            if accessStarted {
                access.stopAccessing(resolvedDirectory.url)
            }
        }

        return BookmarkedDirectoryAccessResult(
            directory: resolvedDirectory,
            value: try await operation(resolvedDirectory),
            accessStarted: accessStarted
        )
    }
}

public struct BookmarkedDirectoryAccessResult<Result>: Sendable where Result: Sendable {
    public let directory: BookmarkedDirectory
    public let value: Result?
    public let accessStarted: Bool

    public init(directory: BookmarkedDirectory, value: Result?, accessStarted: Bool) {
        self.directory = directory
        self.value = value
        self.accessStarted = accessStarted
    }
}
