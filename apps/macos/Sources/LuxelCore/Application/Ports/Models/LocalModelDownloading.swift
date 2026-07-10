import Foundation

public struct LocalModelArtifactDownloadRequest: Equatable, Sendable {
    public let provider: LocalModelProvider
    public let repository: String
    public let commit: String
    public let artifact: LocalModelArtifact
    public let destinationURL: URL

    public init(
        provider: LocalModelProvider,
        repository: String,
        commit: String,
        artifact: LocalModelArtifact,
        destinationURL: URL
    ) {
        self.provider = provider
        self.repository = repository
        self.commit = commit
        self.artifact = artifact
        self.destinationURL = destinationURL
    }
}

public typealias LocalModelDownloadProgressHandler = @Sendable (Int64) async -> Void

public protocol LocalModelDownloading: Sendable {
    func download(
        _ request: LocalModelArtifactDownloadRequest,
        progress: @escaping LocalModelDownloadProgressHandler
    ) async throws
}
