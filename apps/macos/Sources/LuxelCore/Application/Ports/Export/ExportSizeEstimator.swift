public protocol ExportSizeEstimator: Sendable {
    func estimate(_ request: ExportRequest) async throws -> ExportEstimate
}
