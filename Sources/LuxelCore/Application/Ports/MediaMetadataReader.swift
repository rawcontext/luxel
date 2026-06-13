import Foundation

public protocol MediaMetadataReader: Sendable {
    func readSourceMedia(at fileURL: URL) async throws -> SourceMedia
}
