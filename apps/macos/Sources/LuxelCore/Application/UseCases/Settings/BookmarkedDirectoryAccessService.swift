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
        guard let accessStarted = startAccess(to: resolvedDirectory) else {
            return deniedAccessResult(for: resolvedDirectory)
        }
        defer { stopAccess(to: resolvedDirectory, ifStarted: accessStarted) }
        let value = try operation(resolvedDirectory)
        return BookmarkedDirectoryAccessResult(
            directory: resolvedDirectory,
            value: value,
            accessStarted: accessStarted
        )
    }

    public func withAccess<Result>(
        to directory: BookmarkedDirectory,
        operation: @Sendable (BookmarkedDirectory) async throws -> Result
    ) async rethrows -> BookmarkedDirectoryAccessResult<Result> {
        let resolvedDirectory = resolve(directory)
        guard let accessStarted = startAccess(to: resolvedDirectory) else {
            return deniedAccessResult(for: resolvedDirectory)
        }
        defer { stopAccess(to: resolvedDirectory, ifStarted: accessStarted) }
        return BookmarkedDirectoryAccessResult(
            directory: resolvedDirectory,
            value: try await operation(resolvedDirectory),
            accessStarted: accessStarted
        )
    }

    public func withRequiredAccess<Result: Sendable>(
        to directory: BookmarkedDirectory,
        revokedError: @Sendable (URL) -> any Error,
        operation: @Sendable (URL) async throws -> Result
    ) async throws -> Result {
        let result = try await withAccess(to: directory) {
            try await operation($0.url)
        }
        guard let value = result.value else {
            throw revokedError(result.directory.url)
        }
        return value
    }

    private func startAccess(to directory: BookmarkedDirectory) -> Bool? {
        guard directory.accessState != .revoked else {
            return nil
        }
        return access.startAccessing(directory.url)
    }

    private func stopAccess(to directory: BookmarkedDirectory, ifStarted accessStarted: Bool) {
        if accessStarted {
            access.stopAccessing(directory.url)
        }
    }

    private func deniedAccessResult<Result: Sendable>(
        for directory: BookmarkedDirectory
    ) -> BookmarkedDirectoryAccessResult<Result> {
        BookmarkedDirectoryAccessResult(
            directory: directory,
            value: nil,
            accessStarted: false
        )
    }
}

public func withBookmarkedDirectoryAccess<Result: Sendable>(
    outputDirectory: URL,
    bookmark: BookmarkedDirectory?,
    service: BookmarkedDirectoryAccessService?,
    revokedError: @Sendable (URL) -> any Error,
    operation: @Sendable (URL) async throws -> Result
) async throws -> Result {
    guard let bookmark, let service else {
        return try await operation(outputDirectory)
    }
    return try await service.withRequiredAccess(
        to: bookmark,
        revokedError: revokedError,
        operation: { resolvedRoot in
            let root = bookmark.url.standardizedFileURL.path
            let destination = outputDirectory.standardizedFileURL.path
            if destination == root {
                return try await operation(resolvedRoot)
            }
            guard destination.hasPrefix(root + "/") else {
                throw revokedError(outputDirectory)
            }
            return try await operation(resolvedRoot.appending(path: String(destination.dropFirst(root.count + 1))))
        }
    )
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
