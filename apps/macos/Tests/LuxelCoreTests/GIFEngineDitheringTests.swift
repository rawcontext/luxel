import Foundation
import LuxelCore
import Testing

extension GIFEngineModelTests {
    @Test("auto dithering chooses none for low error and diffusion for high error")
    func autoDitheringChoosesNoneForLowErrorAndDiffusionForHighError() throws {
        let palette = try blackWhitePalette()
        let exactFrame = try blackWhiteFrame()
        let highErrorFrame = try solidBitmap(
            width: 2, height: 1, color: GIFRGBAPixel(red: 96, green: 96, blue: 96))
        let heuristic = GIFDitheringHeuristic()

        #expect(try heuristic.meanQuantizationError(for: [exactFrame], palette: palette) == 0)
        #expect(try heuristic.resolvedMode(for: [exactFrame], palette: palette) == .none)
        #expect(try heuristic.resolvedMode(for: [highErrorFrame], palette: palette) == .diffusion)
        #expect(throws: GIFEngineModelError.invalidFrameCount) {
            _ = try heuristic.meanQuantizationError(for: [], palette: palette)
        }
    }

    @Test("frame indexer routes explicit and auto dithering modes")
    func frameIndexerRoutesExplicitAndAutoDitheringModes() throws {
        let palette = try blackWhitePalette()
        let exactFrame = try blackWhiteFrame()
        let highErrorFrame = try solidBitmap(
            width: 3,
            height: 1,
            color: GIFRGBAPixel(red: 96, green: 96, blue: 96)
        )
        let indexer = GIFFrameIndexer()

        let exactAuto = try indexer.indexedFrame(from: exactFrame, palette: palette, dithering: .auto)
        let highErrorAuto = try indexer.indexedFrame(
            from: highErrorFrame, palette: palette, dithering: .auto)
        let highErrorNone = try indexer.indexedFrame(
            from: highErrorFrame, palette: palette, dithering: .none)
        let highErrorDiffusion = try indexer.indexedFrame(
            from: highErrorFrame, palette: palette, dithering: .diffusion)
        let sharedAuto = try indexer.indexedFrames(
            from: [exactFrame, highErrorFrame],
            palette: palette,
            dithering: .auto
        )

        #expect(exactAuto.colorIndexes == [0, 1])
        #expect(highErrorNone.colorIndexes == [0, 0, 0])
        #expect(highErrorDiffusion.colorIndexes == [0, 1, 0])
        #expect(highErrorAuto == highErrorDiffusion)
        #expect(sharedAuto.map(\.colorIndexes) == [[0, 1], [0, 1, 0]])
        #expect(throws: GIFEngineModelError.invalidFrameCount) {
            _ = try indexer.indexedFrames(from: [], palette: palette, dithering: .none)
        }
    }

    private func blackWhiteFrame() throws -> GIFFrameBitmap {
        try GIFFrameBitmap(
            pixelSize: PixelSize(width: 2, height: 1),
            pixels: [
                GIFRGBAPixel(red: 0, green: 0, blue: 0),
                GIFRGBAPixel(red: 255, green: 255, blue: 255)
            ]
        )
    }

    @Test("frame differ emits full first frame and transparent static deltas")
    func frameDifferEmitsFullFirstFrameAndTransparentStaticDeltas() throws {
        let bitmap = try solidBitmap(
            width: 3, height: 2, color: GIFRGBAPixel(red: 10, green: 20, blue: 30))
        let indexed = try indexedFrame(width: 3, height: 2, indexes: [1, 2, 3, 4, 5, 6])
        let differ = GIFFrameDiffer()

        let first = try differ.delta(
            from: nil, to: bitmap, indexedFrame: indexed, transparentColorIndex: 0)
        let repeated = try differ.delta(
            from: bitmap, to: bitmap, indexedFrame: indexed, transparentColorIndex: 0)

        #expect(first.rect == (try GIFPixelRect(x: 0, y: 0, width: 3, height: 2)))
        #expect(first.colorIndexes == [1, 2, 3, 4, 5, 6])
        #expect(first.transparentColorIndex == 0)
        #expect(first.disposal == .doNotDispose)
        #expect(repeated.rect == (try GIFPixelRect(x: 0, y: 0, width: 1, height: 1)))
        #expect(repeated.colorIndexes == [0])
        #expect(repeated.transparentColorIndex == 0)
        #expect(repeated.disposal == .doNotDispose)
    }

    @Test("frame differ crops moving regions to changed bounds")
    func frameDifferCropsMovingRegionsToChangedBounds() throws {
        let previous = try solidBitmap(
            width: 4, height: 3, color: GIFRGBAPixel(red: 0, green: 0, blue: 0))
        let current = try bitmap(
            width: 4,
            height: 3,
            changedPixels: [
                ChangedPixel(x: 1, y: 1, pixel: GIFRGBAPixel(red: 255, green: 0, blue: 0)),
                ChangedPixel(x: 2, y: 1, pixel: GIFRGBAPixel(red: 255, green: 0, blue: 0)),
                ChangedPixel(x: 1, y: 2, pixel: GIFRGBAPixel(red: 255, green: 0, blue: 0)),
                ChangedPixel(x: 2, y: 2, pixel: GIFRGBAPixel(red: 255, green: 0, blue: 0))
            ]
        )
        let indexed = try indexedFrame(width: 4, height: 3, indexes: Array(0...11))

        let delta = try GIFFrameDiffer().delta(
            from: previous,
            to: current,
            indexedFrame: indexed,
            transparentColorIndex: 0
        )

        #expect(delta.rect == (try GIFPixelRect(x: 1, y: 1, width: 2, height: 2)))
        #expect(delta.colorIndexes == [5, 6, 9, 10])
    }

    @Test("frame differ applies lossy tolerance before differencing")
    func frameDifferAppliesLossyToleranceBeforeDifferencing() throws {
        let previous = try solidBitmap(
            width: 2, height: 1, color: GIFRGBAPixel(red: 10, green: 10, blue: 10))
        let current = try bitmap(
            width: 2,
            height: 1,
            baseColor: GIFRGBAPixel(red: 10, green: 10, blue: 10),
            changedPixels: [
                ChangedPixel(x: 0, y: 0, pixel: GIFRGBAPixel(red: 14, green: 10, blue: 10))
            ]
        )
        let indexed = try indexedFrame(width: 2, height: 1, indexes: [7, 8])
        let differ = GIFFrameDiffer()

        let tolerated = try differ.delta(
            from: previous,
            to: current,
            indexedFrame: indexed,
            transparentColorIndex: 0,
            lossyTolerance: 4
        )
        let strict = try differ.delta(
            from: previous,
            to: current,
            indexedFrame: indexed,
            transparentColorIndex: 0,
            lossyTolerance: 3
        )

        #expect(tolerated.rect == (try GIFPixelRect(x: 0, y: 0, width: 1, height: 1)))
        #expect(tolerated.colorIndexes == [0])
        #expect(strict.rect == (try GIFPixelRect(x: 0, y: 0, width: 1, height: 1)))
        #expect(strict.colorIndexes == [7])
    }

    @Test("frame differ rejects invalid geometry and mismatched frames")
    func frameDifferRejectsInvalidGeometryAndMismatchedFrames() throws {
        let previous = try solidBitmap(
            width: 2, height: 2, color: GIFRGBAPixel(red: 0, green: 0, blue: 0))
        let current = try solidBitmap(
            width: 3, height: 2, color: GIFRGBAPixel(red: 0, green: 0, blue: 0))
        let indexed = try indexedFrame(width: 3, height: 2, indexes: [0, 1, 2, 3, 4, 5])
        let wrongIndexed = try indexedFrame(width: 2, height: 2, indexes: [0, 1, 2, 3])

        #expect(throws: GIFEngineModelError.frameSizeMismatch) {
            _ = try GIFFrameDiffer().delta(from: previous, to: current, indexedFrame: indexed)
        }
        #expect(throws: GIFEngineModelError.frameSizeMismatch) {
            _ = try GIFFrameDiffer().delta(from: nil, to: current, indexedFrame: wrongIndexed)
        }
        #expect(throws: GIFEngineModelError.invalidLossyTolerance) {
            _ = try GIFFrameDiffer().delta(
                from: nil, to: current, indexedFrame: indexed, lossyTolerance: 33)
        }
        #expect(throws: GIFEngineModelError.invalidPixelRect) {
            _ = try GIFPixelRect(x: 0, y: 0, width: 0, height: 1)
        }
    }

    func solidBitmap(width: Int, height: Int, color: GIFRGBAPixel) throws -> GIFFrameBitmap {
        try GIFFrameBitmap(
            pixelSize: PixelSize(width: width, height: height),
            pixels: Array(repeating: color, count: width * height)
        )
    }

    private func bitmap(
        width: Int,
        height: Int,
        baseColor: GIFRGBAPixel = GIFRGBAPixel(red: 0, green: 0, blue: 0),
        changedPixels: [ChangedPixel]
    ) throws -> GIFFrameBitmap {
        var pixels = Array(
            repeating: baseColor,
            count: width * height
        )

        for changedPixel in changedPixels {
            pixels[changedPixel.row * width + changedPixel.column] = changedPixel.pixel
        }

        return try GIFFrameBitmap(
            pixelSize: PixelSize(width: width, height: height),
            pixels: pixels
        )
    }

    private func indexedFrame(width: Int, height: Int, indexes: [UInt8]) throws -> GIFIndexedFrame {
        try GIFIndexedFrame(
            pixelSize: PixelSize(width: width, height: height),
            colorIndexes: indexes
        )
    }

    func blackWhitePalette() throws -> GIFColorPalette {
        try GIFColorPalette(colors: [
            GIFPaletteColor(red: 0, green: 0, blue: 0),
            GIFPaletteColor(red: 255, green: 255, blue: 255)
        ])
    }
}

private struct ChangedPixel {
    let column: Int
    let row: Int
    let pixel: GIFRGBAPixel

    init(x column: Int, y row: Int, pixel: GIFRGBAPixel) {
        self.column = column
        self.row = row
        self.pixel = pixel
    }
}
