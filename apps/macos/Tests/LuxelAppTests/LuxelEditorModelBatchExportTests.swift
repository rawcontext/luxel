import Foundation
import LuxelCore
import Testing

@testable import LuxelPresentation

extension LuxelEditorModelTests {
    @Test("batch export runs selected formats and exposes job rows")
    func batchExportRunsSelectedFormatsAndExposesJobRows() async throws {
        let exporter = SpyMediaExporter()
        let fileSystem = SpyFileSystem()
        let fileActionClient = StubExportedFileActionClient()
        var rememberedFormats: [ExportFormat] = []
        let model = makeModel(
            exporter: exporter,
            fileSystem: fileSystem,
            fileActionClient: fileActionClient,
            configuration: .init(onExportMemoryChange: { format, _ in
                rememberedFormats.append(format)
            })
        )
        let batchDirectory = URL(fileURLWithPath: "/tmp/source Export", isDirectory: true)

        await model.open(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.setFormatSelection(.hevc, isSelected: true)
        model.setFormatSelection(.gif, isSelected: true)
        model.setGIFLoopModeKind(.bounce)
        model.setGIFDithering(.diffusion)
        model.startExport()

        while model.isExporting {
            try await Task.sleep(for: .milliseconds(10))
        }

        let captured = await exporter.capturedExports()
        let expectedGIFOptions = try GIFRenderOptions(
            quality: .balanced,
            loopMode: .bounce,
            dithering: .diffusion
        )

        expectCapturedBatchExports(captured, expectedGIFOptions: expectedGIFOptions)
        #expect(fileSystem.createdDirectories == [batchDirectory])
        expectCompletedBatchPresentation(model, batchDirectory: batchDirectory)
        model.openExportedFile()
        #expect(fileActionClient.openedURLs == [batchDirectory])
        #expect(rememberedFormats == [.hevc, .mp4, .gif])
    }

    private func expectCapturedBatchExports(
        _ captured: [(request: ExportRequest, outputFileURL: URL)],
        expectedGIFOptions: GIFRenderOptions
    ) {
        let capturedByFormat = Dictionary(
            uniqueKeysWithValues: captured.map { ($0.request.format, $0) })
        #expect(Set(captured.map(\.request.format)) == [.hevc, .mp4, .gif])
        #expect(capturedByFormat[.hevc]?.request.gifOptions == nil)
        #expect(capturedByFormat[.mp4]?.request.gifOptions == nil)
        #expect(capturedByFormat[.gif]?.request.gifOptions == expectedGIFOptions)
        #expect(
            Set(captured.map(\.outputFileURL.path)) == [
                "/tmp/source Export/source Export HEVC.mp4",
                "/tmp/source Export/source Export H.264.mp4",
                "/tmp/source Export/source Export GIF.gif"
            ])
    }

    private func expectCompletedBatchPresentation(
        _ model: LuxelEditorModel,
        batchDirectory: URL
    ) {
        #expect(
            model.status
                == .exportedBatch([
                    URL(fileURLWithPath: "/tmp/source Export/source Export HEVC.mp4"),
                    URL(fileURLWithPath: "/tmp/source Export/source Export H.264.mp4"),
                    URL(fileURLWithPath: "/tmp/source Export/source Export GIF.gif")
                ]))
        #expect(model.exportPanelMessage == "3 files exported")
        #expect(model.exportProgressValue == 1)
        #expect(!model.canRetryExport)
        #expect(model.exportedOpenURL == batchDirectory)
        #expect(model.exportJobs.map(\.format) == [.hevc, .mp4, .gif])
        #expect(model.exportJobs.map(\.statusSummary) == ["Complete", "Complete", "Complete"])
        #expect(
            model.exportJobs.compactMap(\.fileURL).map(\.path) == [
                "/tmp/source Export/source Export HEVC.mp4",
                "/tmp/source Export/source Export H.264.mp4",
                "/tmp/source Export/source Export GIF.gif"
            ])
    }
}
