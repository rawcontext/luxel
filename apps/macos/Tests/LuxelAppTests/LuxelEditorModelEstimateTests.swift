import Foundation
import LuxelCore
import Testing

@testable import LuxelPresentation

@MainActor
extension LuxelEditorModelTests {
    @Test("unsupported estimate clears stale value")
    func unsupportedEstimateClearsStaleValue() async throws {
        let model = makeModel(exportSizeEstimator: StubFailingExportSizeEstimator())

        model.exportEstimate = try ExportEstimate(bytes: 42, confidence: .modeled)
        await model.open(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            outputDirectory: URL(fileURLWithPath: "/tmp"))
        await model.refreshExportEstimate()

        #expect(model.exportEstimate == nil)
        #expect(model.exportEstimateSummary == nil)
    }
}
