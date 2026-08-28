import Foundation
import LuxelCore

struct ResolvedCommandLineAccess {
    let summary: CommandLineFolderGrantSummary
    let bookmark: BookmarkedDirectory?
}

@MainActor
extension LuxelMenuModel {
    func addCommandLineAccess(suggestedPath: String?) throws -> CommandLineAutomationResult {
        let suggested = suggestedPath.map(URL.init(fileURLWithPath:)) ?? settings.recordingsDirectory
        guard let directory = try bookmarkedDirectoryPicker.chooseDirectory(currentDirectory: suggested)
        else {
            throw LuxelCommandLineAutomationError.folderSelectionCanceled
        }
        if let existing = settings.commandLineFolderGrants.first(where: {
            $0.directory.url.standardizedFileURL == directory.url.standardizedFileURL
        }) {
            return CommandLineAutomationResult(grant: commandLineGrantSummary(existing))
        }
        let grant = CommandLineFolderGrant(directory: directory)
        settings.commandLineFolderGrants.append(grant)
        saveSettings()
        return CommandLineAutomationResult(grant: commandLineGrantSummary(grant))
    }

    func commandLineDoctorReport() -> CommandLineDoctorReport {
        CommandLineDoctorReport(
            appVersion: appMetadata.version,
            appBuild: appMetadata.build,
            commandLineControlEnabled: settings.commandLineControlEnabled,
            recordingsDirectoryPath: settings.recordingsDirectory.path,
            screenRecordingStatus: commandLinePermissionName(screenRecordingStatus),
            microphoneStatus: commandLinePermissionName(microphoneStatus),
            cameraStatus: commandLinePermissionName(cameraStatus)
        )
    }

    private func commandLinePermissionName(_ status: PermissionStatus) -> String {
        switch status {
        case .notDetermined: "notDetermined"
        case .authorized: "authorized"
        case .denied: "denied"
        case .restricted: "restricted"
        case .unknown: "unknown"
        }
    }

    func commandLineAccessSummaries() -> [CommandLineFolderGrantSummary] {
        let movies =
            FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Movies")
        var summaries = [
            CommandLineFolderGrantSummary(
                id: stableCommandLineGrantID("movies"),
                path: movies.path,
                source: .movies,
                status: .resolved
            )
        ]
        summaries.append(
            CommandLineFolderGrantSummary(
                id: stableCommandLineGrantID("recordings"),
                path: settings.recordingsDirectory.path,
                source: .recordings,
                status: settings.recordingsDirectoryBookmark?.accessState ?? .resolved
            ))
        summaries.append(contentsOf: settings.commandLineFolderGrants.map(commandLineGrantSummary))
        return summaries
    }

    private func commandLineGrantSummary(_ grant: CommandLineFolderGrant)
        -> CommandLineFolderGrantSummary {
        CommandLineFolderGrantSummary(
            id: grant.id,
            path: grant.directory.url.path,
            source: .additional,
            status: grant.directory.accessState
        )
    }

    private func stableCommandLineGrantID(_ value: String) -> UUID {
        let hex = CommandLineAutomationAuthentication.digest(Data(value.utf8))
        let components = [
            String(hex.prefix(8)),
            String(hex.dropFirst(8).prefix(4)),
            "4\(hex.dropFirst(13).prefix(3))",
            "8\(hex.dropFirst(17).prefix(3))",
            String(hex.dropFirst(20).prefix(12))
        ]
        return UUID(uuidString: components.joined(separator: "-"))!
    }

    func commandLineAccess(for url: URL) throws -> ResolvedCommandLineAccess {
        let target = canonicalCommandLineURL(url)
        if path(target, isInside: settings.recordingsDirectory) {
            return ResolvedCommandLineAccess(
                summary: commandLineAccessSummaries()[1],
                bookmark: settings.recordingsDirectoryBookmark
            )
        }
        let movies =
            FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Movies")
        if path(target, isInside: movies) {
            return ResolvedCommandLineAccess(summary: commandLineAccessSummaries()[0], bookmark: nil)
        }
        for grant in settings.commandLineFolderGrants where path(target, isInside: grant.directory.url) {
            return ResolvedCommandLineAccess(
                summary: commandLineGrantSummary(grant),
                bookmark: grant.directory
            )
        }
        throw LuxelCommandLineAutomationError.fileAccessRequired(target.path)
    }

    private func path(_ target: URL, isInside directory: URL) -> Bool {
        let targetPath = canonicalCommandLineURL(target).path
        let rootPath = canonicalCommandLineURL(directory).path
        return targetPath == rootPath || targetPath.hasPrefix(rootPath + "/")
    }

    private func canonicalCommandLineURL(_ url: URL) -> URL {
        let standardized = url.standardizedFileURL
        if FileManager.default.fileExists(atPath: standardized.path) {
            return standardized.resolvingSymlinksInPath()
        }
        return standardized.deletingLastPathComponent().resolvingSymlinksInPath()
            .appending(path: standardized.lastPathComponent)
    }

    func withCommandLineFileAccess<Result: Sendable>(
        paths: [URL],
        operation: @escaping @MainActor @Sendable () async throws -> Result
    ) async throws -> Result {
        var bookmarks: [BookmarkedDirectory] = []
        for path in paths {
            if let bookmark = try commandLineAccess(for: path).bookmark,
                !bookmarks.contains(where: { $0.url == bookmark.url }) {
                bookmarks.append(bookmark)
            }
        }
        return try await withCommandLineBookmarks(bookmarks, index: 0, operation: operation)
    }

    private func withCommandLineBookmarks<Result: Sendable>(
        _ bookmarks: [BookmarkedDirectory],
        index: Int,
        operation: @escaping @MainActor @Sendable () async throws -> Result
    ) async throws -> Result {
        guard index < bookmarks.count else { return try await operation() }
        let bookmark = bookmarks[index]
        let result = try await directoryAccessService.withAccess(to: bookmark) { _ in
            try await withCommandLineBookmarks(bookmarks, index: index + 1, operation: operation)
        }
        guard let value = result.value else {
            throw LuxelCommandLineAutomationError.fileAccessRevoked(bookmark.url.path)
        }
        return value
    }
}
