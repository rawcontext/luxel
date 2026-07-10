import Foundation

public struct ExportAudioPreparationProgress: Equatable, Sendable {
    public let requestIndices: [Int]
    public let progress: Double

    public init(requestIndices: [Int], progress: Double) {
        self.requestIndices = requestIndices
        self.progress = min(max(progress, 0), 1)
    }
}

public typealias ExportAudioPreparationProgressHandler =
    @Sendable (ExportAudioPreparationProgress) async -> Void

public protocol ExportAudioPreparing: Sendable {
    func prepareAudio(
        for requests: [ExportRequest],
        progress: ExportAudioPreparationProgressHandler?
    ) async throws -> PreparedExportAudioSet
}

public struct PreparedExportAudioSet: Sendable {
    private let assetsByRequestIndex: [Int: PreparedAudioAsset]
    private let cleanup: PreparedAudioCleanup

    public init() {
        assetsByRequestIndex = [:]
        cleanup = PreparedAudioCleanup(directoryURL: nil)
    }

    public init(
        assetsByRequestIndex: [Int: PreparedAudioAsset],
        temporaryDirectoryURL: URL? = nil
    ) {
        self.assetsByRequestIndex = assetsByRequestIndex
        cleanup = PreparedAudioCleanup(directoryURL: temporaryDirectoryURL)
    }

    init(
        assetsByRequestIndex: [Int: PreparedAudioAsset],
        directoryURL: URL
    ) {
        self.assetsByRequestIndex = assetsByRequestIndex
        cleanup = PreparedAudioCleanup(directoryURL: directoryURL)
    }

    public func asset(forRequestAt index: Int) -> PreparedAudioAsset? {
        assetsByRequestIndex[index]
    }

    public func removeTemporaryFiles() {
        cleanup.remove()
    }
}

private final class PreparedAudioCleanup: @unchecked Sendable {
    private let directoryURL: URL?
    private let lock = NSLock()
    private var didRemove = false

    init(directoryURL: URL?) {
        self.directoryURL = directoryURL
    }

    func remove() {
        lock.lock()
        let shouldRemove = !didRemove
        didRemove = true
        lock.unlock()

        guard shouldRemove, let directoryURL else {
            return
        }
        try? FileManager.default.removeItem(at: directoryURL)
    }
}

public struct UnavailableExportAudioPreparer: ExportAudioPreparing {
    public init() {}

    public func prepareAudio(
        for requests: [ExportRequest],
        progress: ExportAudioPreparationProgressHandler?
    ) async throws -> PreparedExportAudioSet {
        guard !requests.contains(where: \.requiresAudioPreparation) else {
            throw ExportAudioPreparationError.preparerUnavailable
        }
        return PreparedExportAudioSet()
    }
}
