import Foundation
import LuxelCore
import Testing

@testable import LuxelPresentation

extension LuxelEditorModelTests {
    @Test("successful export emits format memory")
    func successfulExportEmitsFormatMemory() async throws {
        var captured: [(ExportFormat, ExportMemory)] = []
        let model = makeModel { format, memory in
            captured.append((format, memory))
        }

        await model.open(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.setFormat(.hevc)
        model.setSizePreset(.percent50)
        model.setFrameRate(24)
        model.setQuality(.high)
        model.startExport()

        while model.isExporting {
            try await Task.sleep(for: .milliseconds(10))
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
        var captured: [(ExportFormat, ExportMemory)] = []
        let model = makeModel { format, memory in
            captured.append((format, memory))
        }

        await model.open(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.setFormat(.gif)
        model.setSizePreset(.percent50)
        model.setFrameRate(12)
        model.setQuality(.compact)
        model.setGIFLoopModeKind(.count)
        model.setGIFLoopCount(6)
        model.setGIFDithering(.ordered)
        model.startExport()

        while model.isExporting {
            try await Task.sleep(for: .milliseconds(10))
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
        var captured: [(ExportFormat, ExportMemory)] = []
        let model = makeModel { format, memory in
            captured.append((format, memory))
        }

        await model.open(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            outputDirectory: URL(fileURLWithPath: "/tmp"))
        model.setFormat(.apng)
        model.setSizePreset(.percent50)
        model.setFrameRate(12)
        model.setGIFLoopModeKind(.none)
        model.startExport()

        while model.isExporting {
            try await Task.sleep(for: .milliseconds(10))
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
}
