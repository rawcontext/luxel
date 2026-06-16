import Foundation
import LuxelCore
import Testing

@Suite("Export presets")
struct ExportPresetTests {
    @Test("built-in defaults match quick recording workflow")
    func builtInDefaultsMatchQuickRecordingWorkflow() throws {
        let presets = ExportPreset.builtInDefaults

        let quickGIF = try #require(presets.first { $0.id == ExportPreset.quickGIFID })
        #expect(quickGIF.name == "Quick GIF")
        #expect(quickGIF.format == .gif)
        #expect(quickGIF.sizeRule == .maxWidth(960))
        #expect(quickGIF.frameRate == (try FrameRate(30)))
        #expect(quickGIF.destination == .clipboard)
        #expect(quickGIF.effectivePostAction == .copyToClipboard)

        let quickMP4 = try #require(presets.first { $0.id == ExportPreset.quickMP4ID })
        #expect(quickMP4.name == "Quick MP4")
        #expect(quickMP4.format == .mp4)
        #expect(quickMP4.sizeRule == .original)
        #expect(quickMP4.frameRate == nil)
        #expect(quickMP4.destination == .recordingsDirectory)
        #expect(quickMP4.effectivePostAction == .revealInFinder)
    }

    @Test("preset resolves source media into export request")
    func presetResolvesSourceMediaIntoExportRequest() throws {
        let preset = try ExportPreset(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
            name: "Small GIF",
            format: .gif,
            sizeRule: .maxWidth(960),
            frameRate: FrameRate(30),
            destination: .clipboard,
            postAction: .none
        )
        let source = try makeSource(width: 1920, height: 1080, frameRate: 60)

        let request = try preset.resolvedRequest(source: source)

        #expect(request.inputFileURL == source.fileURL)
        #expect(request.format == .gif)
        #expect(request.pixelSize == (try PixelSize(width: 960, height: 540)))
        #expect(request.frameRate == (try FrameRate(30)))
        #expect(request.timeRange == (try TimeRange(start: 0, end: source.duration)))
        #expect(!request.shouldMute)
        #expect(request.outputShouldMute)
        #expect(!request.shouldCrop)
        #expect(preset.effectivePostAction == .copyToClipboard)
    }

    @Test("preset frame rate is capped by source")
    func presetFrameRateIsCappedBySource() throws {
        let preset = try ExportPreset(
            name: "Capped GIF",
            format: .gif,
            sizeRule: .original,
            frameRate: FrameRate(30),
            destination: .recordingsDirectory,
            postAction: .none
        )
        let request = try preset.resolvedRequest(source: makeSource(width: 640, height: 360, frameRate: 12))

        #expect(request.frameRate == (try FrameRate(12)))
    }

    @Test("max width does not upscale source media")
    func maxWidthDoesNotUpscaleSourceMedia() throws {
        let sourceSize = try PixelSize(width: 640, height: 360)

        #expect(try ExportPresetSizeRule.maxWidth(960).pixelSize(for: sourceSize) == sourceSize)
    }

    @Test("size preset delegates to editor size preset")
    func sizePresetDelegatesToEditorSizePreset() throws {
        let sourceSize = try PixelSize(width: 1920, height: 1080)

        #expect(
            try ExportPresetSizeRule.preset(.percent50).pixelSize(for: sourceSize)
                == PixelSize(width: 960, height: 540)
        )
    }

    @Test("source media without audio mutes preset request")
    func sourceMediaWithoutAudioMutesPresetRequest() throws {
        let preset = try ExportPreset(
            name: "Muted MP4",
            format: .mp4,
            sizeRule: .original,
            frameRate: nil,
            destination: .recordingsDirectory,
            postAction: .none
        )

        #expect(try preset.resolvedRequest(source: makeSource(hasAudio: false)).outputShouldMute)
    }

    @Test("invalid presets throw")
    func invalidPresetsThrow() {
        #expect(throws: ExportPresetError.invalidName) {
            _ = try ExportPreset(
                name: "  ",
                format: .mp4,
                sizeRule: .original,
                frameRate: nil,
                destination: .recordingsDirectory,
                postAction: .none
            )
        }

        #expect(throws: ExportPresetError.invalidMaxWidth) {
            _ = try ExportPreset(
                name: "Invalid Width",
                format: .gif,
                sizeRule: .maxWidth(0),
                frameRate: nil,
                destination: .recordingsDirectory,
                postAction: .none
            )
        }
    }

    private func makeSource(
        width: Int = 1280,
        height: Int = 720,
        frameRate: Int = 30,
        hasAudio: Bool = true
    ) throws -> SourceMedia {
        try SourceMedia(
            fileURL: URL(fileURLWithPath: "/tmp/source.mp4"),
            duration: 12.5,
            pixelSize: PixelSize(width: width, height: height),
            nominalFrameRate: FrameRate(frameRate),
            hasAudio: hasAudio
        )
    }
}
