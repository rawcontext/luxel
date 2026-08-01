import Foundation
import LuxelCore
import Testing

@testable import LuxelPresentation

extension LuxelEditorModelTests {
    @Test("successful export emits format memory")
    func successfulExportEmitsFormatMemory() async throws {
        let captured = try await exportedMemory(format: .hevc) { model in
            model.setSizePreset(.percent50)
            model.setFrameRate(24)
            model.setQuality(.high)
        }

        let expectedMemory = try ExportMemory(
            sizePreset: .percent50,
            frameRate: FrameRate(24),
            quality: .high
        )
        #expect(captured.count == 1)
        #expect(captured.first?.0 == .hevc)
        #expect(captured.first?.1 == expectedMemory)
    }

    @Test("successful GIF export emits GIF memory")
    func successfulGIFExportEmitsGIFMemory() async throws {
        let captured = try await exportedMemory(format: .gif) { model in
            model.setSizePreset(.percent50)
            model.setFrameRate(12)
            model.setQuality(.compact)
            model.setGIFLoopModeKind(.count)
            model.setGIFLoopCount(6)
            model.setGIFDithering(.ordered)
        }

        let expectedMemory = try ExportMemory(
            sizePreset: .percent50,
            frameRate: FrameRate(12),
            quality: .compact,
            gifOptions: GIFRenderOptions(
                quality: .compact,
                loopMode: .counted(6),
                dithering: .ordered
            )
        )
        #expect(captured.count == 1)
        #expect(captured.first?.0 == .gif)
        #expect(captured.first?.1 == expectedMemory)
    }

    @Test("successful APNG export emits loop memory")
    func successfulAPNGExportEmitsLoopMemory() async throws {
        let captured = try await exportedMemory(format: .apng) { model in
            model.setSizePreset(.percent50)
            model.setFrameRate(12)
            model.setGIFLoopModeKind(.none)
        }

        let expectedMemory = try ExportMemory(
            sizePreset: .percent50,
            frameRate: FrameRate(12),
            quality: .lossless,
            gifOptions: GIFRenderOptions(loopMode: .none)
        )
        #expect(captured.count == 1)
        #expect(captured.first?.0 == .apng)
        #expect(captured.first?.1 == expectedMemory)
    }

    private func exportedMemory(
        format: ExportFormat,
        configure: (LuxelEditorModel) -> Void
    ) async throws -> [(ExportFormat, ExportMemory)] {
        var captured: [(ExportFormat, ExportMemory)] = []
        let model = makeModel(
            configuration: .init(onExportMemoryChange: { format, memory in
                captured.append((format, memory))
            })
        )
        await model.open(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            outputDirectory: URL(fileURLWithPath: "/tmp")
        )
        model.setFormat(format)
        configure(model)
        model.startExport()
        while model.isExporting {
            try await Task.sleep(for: .milliseconds(10))
        }
        return captured
    }
}
