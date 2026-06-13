import Foundation

public struct PassthroughExportService: Sendable {
    private let fileSystem: any FileSystem
    private let trimmedExporter: (any PassthroughExporter)?

    public init(
        fileSystem: any FileSystem,
        trimmedExporter: (any PassthroughExporter)? = nil
    ) {
        self.fileSystem = fileSystem
        self.trimmedExporter = trimmedExporter
    }

    public func export(_ request: PassthroughExportRequest) async throws -> PassthroughExportResult {
        if request.inputFileURL.standardizedFileURL == request.outputFileURL.standardizedFileURL {
            guard request.timeRange == nil else {
                throw PassthroughExportError.sameSourceAndDestination
            }

            return PassthroughExportResult(fileURL: request.outputFileURL)
        }

        try fileSystem.createDirectory(at: request.outputFileURL.deletingLastPathComponent())

        if fileSystem.fileExists(at: request.outputFileURL) {
            try fileSystem.removeFile(at: request.outputFileURL)
        }

        if request.timeRange != nil {
            guard let trimmedExporter else {
                throw PassthroughExportError.trimmedPassthroughUnavailable
            }

            return try await trimmedExporter.export(request)
        }

        try fileSystem.copyFile(from: request.inputFileURL, to: request.outputFileURL)
        return PassthroughExportResult(fileURL: request.outputFileURL)
    }
}

public enum PassthroughExportError: Error, Equatable {
    case trimmedPassthroughUnavailable
    case sameSourceAndDestination
}
