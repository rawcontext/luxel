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
            fileActionClient: fileActionClient
        ) { format, _ in
            rememberedFormats.append(format)
        }
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

        #expect(captured.map(\.request.format) == [.mp4, .hevc, .gif])
        #expect(captured[0].request.gifOptions == nil)
        #expect(captured[1].request.gifOptions == nil)
        #expect(captured[2].request.gifOptions == expectedGIFOptions)
        #expect(
            captured.map(\.outputFileURL.path) == [
                "/tmp/source Export/source Export H264.mp4",
                "/tmp/source Export/source Export H265.mp4",
                "/tmp/source Export/source Export GIF.gif"
            ])
        #expect(fileSystem.createdDirectories == [batchDirectory])
        #expect(
            model.status
                == .exportedBatch([
                    URL(fileURLWithPath: "/tmp/source Export/source Export H264.mp4"),
                    URL(fileURLWithPath: "/tmp/source Export/source Export H265.mp4"),
                    URL(fileURLWithPath: "/tmp/source Export/source Export GIF.gif")
                ]))
        #expect(model.exportPanelMessage == "3 files exported")
        #expect(model.exportProgressValue == 1)
        #expect(!model.canRetryExport)
        #expect(model.exportedOpenURL == batchDirectory)
        #expect(model.exportJobs.map(\.format) == [.mp4, .hevc, .gif])
        #expect(model.exportJobs.map(\.statusSummary) == ["Complete", "Complete", "Complete"])
        #expect(
            model.exportJobs.compactMap(\.fileURL).map(\.path) == [
                "/tmp/source Export/source Export H264.mp4",
                "/tmp/source Export/source Export H265.mp4",
                "/tmp/source Export/source Export GIF.gif"
            ])
        model.openExportedFile()
        #expect(fileActionClient.openedURLs == [batchDirectory])
        #expect(rememberedFormats == [.mp4, .hevc, .gif])
    }
}
