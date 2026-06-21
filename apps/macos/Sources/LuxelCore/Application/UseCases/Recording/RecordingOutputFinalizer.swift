import Foundation

public struct RecordingOutputFinalizationPlan: Equatable, Sendable {
    public let stagingFileURL: URL
    public let finalFileURL: URL
    public let finalDirectoryBookmark: BookmarkedDirectory?

    public init(
        stagingFileURL: URL,
        finalFileURL: URL,
        finalDirectoryBookmark: BookmarkedDirectory? = nil
    ) {
        self.stagingFileURL = stagingFileURL
        self.finalFileURL = finalFileURL
        self.finalDirectoryBookmark = finalDirectoryBookmark
    }

    public static func direct(_ fileURL: URL) -> RecordingOutputFinalizationPlan {
        RecordingOutputFinalizationPlan(
            stagingFileURL: fileURL,
            finalFileURL: fileURL
        )
    }

    public var recordsDirectlyToFinalURL: Bool {
        stagingFileURL == finalFileURL
    }
}

public struct RecordingOutputFinalizationResult: Equatable, Sendable {
    public let fileURL: URL
    public let didUseStagingFallback: Bool

    public init(fileURL: URL, didUseStagingFallback: Bool = false) {
        self.fileURL = fileURL
        self.didUseStagingFallback = didUseStagingFallback
    }
}

public protocol RecordingOutputFinalizer: Sendable {
    func finalize(_ plan: RecordingOutputFinalizationPlan) throws -> RecordingOutputFinalizationResult
}

public struct PassthroughRecordingOutputFinalizer: RecordingOutputFinalizer {
    public init() {}

    public func finalize(_ plan: RecordingOutputFinalizationPlan) throws
    -> RecordingOutputFinalizationResult {
        RecordingOutputFinalizationResult(fileURL: plan.finalFileURL)
    }
}

public struct FileSystemRecordingOutputFinalizer: RecordingOutputFinalizer {
    private let fileSystem: any FileSystem
    private let directoryAccessService: BookmarkedDirectoryAccessService?

    public init(
        fileSystem: any FileSystem,
        directoryAccessService: BookmarkedDirectoryAccessService? = nil
    ) {
        self.fileSystem = fileSystem
        self.directoryAccessService = directoryAccessService
    }

    public func finalize(_ plan: RecordingOutputFinalizationPlan) throws
    -> RecordingOutputFinalizationResult {
        guard !plan.recordsDirectlyToFinalURL else {
            return RecordingOutputFinalizationResult(fileURL: plan.finalFileURL)
        }

        if let result = finalizeWithBookmarkIfAvailable(plan) {
            return result
        }

        return try finalizeWithoutBookmark(plan)
    }

    private func finalizeWithBookmarkIfAvailable(
        _ plan: RecordingOutputFinalizationPlan
    ) -> RecordingOutputFinalizationResult? {
        guard let finalDirectoryBookmark = plan.finalDirectoryBookmark,
              let directoryAccessService
        else {
            return nil
        }

        do {
            let result = try directoryAccessService.withAccess(to: finalDirectoryBookmark) { _ in
                try moveStagingFile(plan)
            }
            return result.value
        } catch {
            return nil
        }
    }

    private func finalizeWithoutBookmark(
        _ plan: RecordingOutputFinalizationPlan
    ) throws -> RecordingOutputFinalizationResult {
        guard fileSystem.fileExists(at: plan.stagingFileURL) else {
            throw RecordingOutputFinalizationError.missingStagingFile(plan.stagingFileURL)
        }

        do {
            return try moveStagingFile(plan)
        } catch {
            guard fileSystem.fileExists(at: plan.stagingFileURL) else {
                throw error
            }

            return RecordingOutputFinalizationResult(
                fileURL: plan.stagingFileURL,
                didUseStagingFallback: true
            )
        }
    }

    private func moveStagingFile(
        _ plan: RecordingOutputFinalizationPlan
    ) throws -> RecordingOutputFinalizationResult {
        try fileSystem.createDirectory(at: plan.finalFileURL.deletingLastPathComponent())
        try fileSystem.moveFile(from: plan.stagingFileURL, to: plan.finalFileURL)
        return RecordingOutputFinalizationResult(fileURL: plan.finalFileURL)
    }
}

public enum RecordingOutputFinalizationError: Error, Equatable, Sendable {
    case missingStagingFile(URL)
}

extension RecordingOutputFinalizationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingStagingFile:
            "No recording output was produced. Try recording again."
        }
    }
}
