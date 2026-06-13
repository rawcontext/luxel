import Foundation

public struct ExportedMedia: Equatable, Sendable {
    public let fileURL: URL
    public let format: ExportFormat
    public let pixelSize: PixelSize
    public let shouldMute: Bool

    public init(fileURL: URL, format: ExportFormat, pixelSize: PixelSize, shouldMute: Bool) {
        self.fileURL = fileURL
        self.format = format
        self.pixelSize = pixelSize
        self.shouldMute = shouldMute
    }
}

public protocol MediaExporter: Sendable {
    func export(_ request: ExportRequest, to outputFileURL: URL) async throws -> ExportedMedia
}
