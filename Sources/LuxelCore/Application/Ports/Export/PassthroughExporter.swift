import Foundation

public protocol PassthroughExporter: Sendable {
    func export(_ request: PassthroughExportRequest) async throws -> PassthroughExportResult
}
