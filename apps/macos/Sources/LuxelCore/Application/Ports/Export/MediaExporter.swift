import Foundation

public struct ExportedMedia: Equatable, Sendable {
    public let fileURL: URL
    public let format: ExportFormat
    public let pixelSize: PixelSize
    public let shouldMute: Bool
    public let fileSizeBytes: Int64?

    public init(
        fileURL: URL,
        format: ExportFormat,
        pixelSize: PixelSize,
        shouldMute: Bool,
        fileSizeBytes: Int64? = nil
    ) {
        self.fileURL = fileURL
        self.format = format
        self.pixelSize = pixelSize
        self.shouldMute = shouldMute
        self.fileSizeBytes = fileSizeBytes
    }

    public func withFileSizeBytes(_ fileSizeBytes: Int64?) -> ExportedMedia {
        ExportedMedia(
            fileURL: fileURL,
            format: format,
            pixelSize: pixelSize,
            shouldMute: shouldMute,
            fileSizeBytes: fileSizeBytes ?? self.fileSizeBytes
        )
    }
}

public typealias MediaExportProgressHandler = @Sendable (Double) async -> Void

public protocol MediaExporter: Sendable {
    func export(
        _ request: ExportRequest,
        to outputFileURL: URL,
        progress: MediaExportProgressHandler?
    ) async throws -> ExportedMedia
}

extension MediaExporter {
    public func export(_ request: ExportRequest, to outputFileURL: URL) async throws -> ExportedMedia {
        try await export(request, to: outputFileURL, progress: nil)
    }
}
