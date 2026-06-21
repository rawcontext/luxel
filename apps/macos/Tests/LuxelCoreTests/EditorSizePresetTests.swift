import LuxelCore
import Testing

@Suite("Editor size presets")
struct EditorSizePresetTests {
    @Test("presets scale source dimensions")
    func presetsScaleSourceDimensions() throws {
        let source = try PixelSize(width: 1920, height: 1080)

        #expect(
            try EditorSizePreset.original.pixelSize(for: source)
                == (try PixelSize(width: 1920, height: 1080)))
        #expect(
            try EditorSizePreset.percent75.pixelSize(for: source)
                == (try PixelSize(width: 1440, height: 810)))
        #expect(
            try EditorSizePreset.percent50.pixelSize(for: source)
                == (try PixelSize(width: 960, height: 540)))
        #expect(
            try EditorSizePreset.percent33.pixelSize(for: source)
                == (try PixelSize(width: 634, height: 356)))
        #expect(
            try EditorSizePreset.percent25.pixelSize(for: source)
                == (try PixelSize(width: 480, height: 270)))
        #expect(
            try EditorSizePreset.percent20.pixelSize(for: source)
                == (try PixelSize(width: 384, height: 216)))
        #expect(
            try EditorSizePreset.percent10.pixelSize(for: source)
                == (try PixelSize(width: 192, height: 108)))
    }

    @Test("presets never produce zero dimensions")
    func presetsNeverProduceZeroDimensions() throws {
        let source = try PixelSize(width: 1, height: 1)

        #expect(
            try EditorSizePreset.percent10.pixelSize(for: source) == (try PixelSize(width: 1, height: 1)))
    }
}
