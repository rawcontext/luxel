public struct ExportSizeEstimationService: Sendable {
    private let estimator: any ExportSizeEstimator

    public init(estimator: any ExportSizeEstimator) {
        self.estimator = estimator
    }

    public func estimate(_ draft: EditorExportDraft) async throws -> ExportEstimate {
        try await estimator.estimate(try draft.exportRequest)
    }

    public func estimate(_ request: ExportRequest) async throws -> ExportEstimate {
        try await estimator.estimate(request)
    }
}
