import Foundation

public struct PassthroughExportService: Sendable {
    private let fileSystem: any FileSystem

    public init(fileSystem: any FileSystem) {
        self.fileSystem = fileSystem
    }

    public func export(_ request: PassthroughExportRequest) async throws -> PassthroughExportResult {
        guard request.timeRange == nil else {
            throw PassthroughExportError.trimmedPassthroughNotImplemented
        }

        if request.inputFileURL.standardizedFileURL == request.outputFileURL.standardizedFileURL {
            return PassthroughExportResult(fileURL: request.outputFileURL)
        }

        try fileSystem.createDirectory(at: request.outputFileURL.deletingLastPathComponent())

        if fileSystem.fileExists(at: request.outputFileURL) {
            try fileSystem.removeFile(at: request.outputFileURL)
        }

        try fileSystem.copyFile(from: request.inputFileURL, to: request.outputFileURL)
        return PassthroughExportResult(fileURL: request.outputFileURL)
    }
}

public enum PassthroughExportError: Error, Equatable {
    case trimmedPassthroughNotImplemented
}
