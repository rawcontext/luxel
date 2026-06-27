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
        #expect(model.exportEstimateSummary(for: model.format) == nil)
        #expect(model.exportEstimatesByFormat.isEmpty)
    }

    @Test("format estimates publish as each format completes")
    func formatEstimatesPublishAsEachFormatCompletes() async throws {
        let model = makeModel(
            exportSizeEstimator: DelayedFormatExportSizeEstimator(delayedFormat: .mp4)
        )

        await model.open(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            outputDirectory: URL(fileURLWithPath: "/tmp"))

        let task = Task {
            await model.refreshExportEstimate()
        }

        for _ in 0..<100 {
            if model.exportEstimatesByFormat[.hevc] != nil {
                break
            }

            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(model.exportEstimateSummary(for: .hevc) == "~ 1.5 MB")
        #expect(model.exportEstimateSummary(for: .mp4) == "Estimating...")

        await task.value

        #expect(model.exportEstimateSummary(for: .mp4) == "~ 1.5 MB")
        #expect(model.estimatingExportSizeFormats.isEmpty)
    }
}
