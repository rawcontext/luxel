import Foundation
import LuxelCore
import Testing

@Suite("GIF engine models")
struct GIFEngineModelTests {
}

extension GIFEngineModelTests {
    @Test("loop modes validate codable storage and ImageIO loop counts")
    func loopModesValidateCodableStorageAndImageIOLoopCounts() throws {
        let counted = try GIFLoopMode.counted(3)

        #expect(GIFLoopMode.forever.imageIOLoopCount == 0)
        #expect(GIFLoopMode.bounce.imageIOLoopCount == 0)
        #expect(GIFLoopMode.none.imageIOLoopCount == nil)
        #expect(counted.imageIOLoopCount == 3)
        #expect(throws: GIFEngineModelError.invalidLoopCount) {
            _ = try GIFLoopMode.counted(0)
        }
        #expect(throws: GIFEngineModelError.invalidLoopCount) {
            _ = try GIFLoopMode.counted(101)
        }

        let data = try JSONEncoder().encode(counted)
        let decoded = try JSONDecoder().decode(GIFLoopMode.self, from: data)
        #expect(decoded == counted)

        let invalidData = Data(#"{"kind":"count","count":0}"#.utf8)
        #expect(throws: GIFEngineModelError.invalidLoopCount) {
            _ = try JSONDecoder().decode(GIFLoopMode.self, from: invalidData)
        }
    }

    @Test("render options validate defaults quality mapping and codable storage")
    func renderOptionsValidateDefaultsQualityMappingAndCodableStorage() throws {
        let standard = GIFRenderOptions.standard
        let compact = try GIFRenderOptions(quality: .compact)
        let balanced = try GIFRenderOptions(quality: .balanced)
        let matte = try RGBColor(red: 0.1, green: 0.2, blue: 0.3)
        let custom = try GIFRenderOptions(
            loopMode: .bounce,
            dithering: .ordered,
            paletteSize: 16,
            lossyTolerance: 4,
            backgroundMatte: matte
        )

        #expect(standard.loopMode == .forever)
        #expect(standard.dithering == .auto)
        #expect(standard.paletteSize == 256)
        #expect(standard.lossyTolerance == 0)
        #expect(standard.backgroundMatte == nil)
        #expect(compact.paletteSize == 128)
        #expect(compact.lossyTolerance == 8)
        #expect(balanced.paletteSize == 256)
        #expect(balanced.lossyTolerance == 0)
        #expect(custom.backgroundMatte == matte)

        let data = try JSONEncoder().encode(custom)
        let decoded = try JSONDecoder().decode(GIFRenderOptions.self, from: data)
        #expect(decoded == custom)

        #expect(throws: GIFEngineModelError.invalidPaletteSize) {
            _ = try GIFRenderOptions(paletteSize: 1)
        }
        #expect(throws: GIFEngineModelError.invalidPaletteSize) {
            _ = try GIFRenderOptions(paletteSize: 257)
        }
        #expect(throws: GIFEngineModelError.invalidLossyTolerance) {
            _ = try GIFRenderOptions(lossyTolerance: 33)
        }
        #expect(throws: GIFEngineModelError.unsupportedQuality(.lossless)) {
            _ = try GIFRenderOptions(quality: .lossless)
        }
        #expect(throws: GIFEngineModelError.invalidColor) {
            _ = try RGBColor(red: 1.1, green: 0, blue: 0)
        }
    }

    @Test("delay planner diffuses centisecond drift")
    func delayPlannerDiffusesCentisecondDrift() throws {
        let frameDuration = 1.0 / 24.0
        let plan = try CentisecondDelayPlanner().plan(
            frameCount: 1_000,
            frameDuration: frameDuration
        )
        let expectedDuration = frameDuration * 1_000

        #expect(Set(plan.centisecondDelays) == [4, 5])
        #expect(abs(plan.totalDuration - expectedDuration) < 0.01)
        #expect(plan.delays.allSatisfy { $0 == 0.04 || $0 == 0.05 })
    }

    @Test("delay planner validates frame counts and durations")
    func delayPlannerValidatesFrameCountsAndDurations() throws {
        let planner = CentisecondDelayPlanner()

        #expect(throws: GIFEngineModelError.invalidFrameCount) {
            _ = try planner.plan(frameCount: 0, frameDuration: 0.1)
        }
        #expect(throws: GIFEngineModelError.invalidFrameDuration) {
            _ = try planner.plan(frameCount: 1, frameDuration: 0)
        }
        #expect(throws: GIFEngineModelError.invalidFrameDuration) {
            _ = try planner.plan(frameDurations: [0.1, .infinity])
        }
        #expect(throws: GIFEngineModelError.invalidCentisecondDelay) {
            _ = try GIFCentisecondDelayPlan(centisecondDelays: [2, 0])
        }
    }

    @Test("frame sequence planner bounces without duplicating the last frame")
    func frameSequencePlannerBouncesWithoutDuplicatingTheLastFrame() throws {
        let planner = GIFFrameSequencePlanner()

        #expect(try planner.frameIndexes(frameCount: 4, loopMode: .forever) == [0, 1, 2, 3])
        #expect(try planner.frameIndexes(frameCount: 4, loopMode: .none) == [0, 1, 2, 3])
        #expect(try planner.frameIndexes(frameCount: 1, loopMode: .bounce) == [0])

        let bounced = try planner.frameIndexes(frameCount: 4, loopMode: .bounce)
        #expect(bounced == [0, 1, 2, 3, 2, 1, 0])
        #expect(bounced.filter { $0 == 3 }.count == 1)

        #expect(throws: GIFEngineModelError.invalidFrameCount) {
            _ = try planner.frameIndexes(frameCount: 0, loopMode: .forever)
        }
        #expect(throws: GIFEngineModelError.invalidLoopCount) {
            _ = try planner.frameIndexes(frameCount: 4, loopMode: .count(0))
        }
    }

    @Test("frame bitmaps validate storage and expose pixel addressing")
    func frameBitmapsValidateStorageAndExposePixelAddressing() throws {
        let pixelSize = try PixelSize(width: 2, height: 2)
        let bitmap = try GIFFrameBitmap(
            pixelSize: pixelSize,
            pixels: [
                GIFRGBAPixel(red: 0, green: 0, blue: 0),
                GIFRGBAPixel(red: 10, green: 20, blue: 30),
                GIFRGBAPixel(red: 40, green: 50, blue: 60),
                GIFRGBAPixel(red: 70, green: 80, blue: 90)
            ]
        )
        let indexed = try GIFIndexedFrame(pixelSize: pixelSize, colorIndexes: [0, 1, 2, 3])

        #expect(try bitmap.pixel(x: 1, y: 0) == GIFRGBAPixel(red: 10, green: 20, blue: 30))
        #expect(try bitmap.linearIndex(x: 0, y: 1) == 2)
        #expect(try indexed.colorIndex(x: 1, y: 1) == 3)
        #expect(throws: GIFEngineModelError.invalidFrameBuffer) {
            _ = try GIFFrameBitmap(
                pixelSize: pixelSize, pixels: [GIFRGBAPixel(red: 0, green: 0, blue: 0)])
        }
        #expect(throws: GIFEngineModelError.invalidFrameBuffer) {
            _ = try GIFIndexedFrame(pixelSize: pixelSize, colorIndexes: [0, 1])
        }
        #expect(throws: GIFEngineModelError.pixelOutOfBounds) {
            _ = try bitmap.pixel(x: 2, y: 0)
        }
    }

    @Test("median cut palette preserves exact small palettes")
    func medianCutPalettePreservesExactSmallPalettes() throws {
        let frame = try GIFFrameBitmap(
            pixelSize: PixelSize(width: 2, height: 2),
            pixels: [
                GIFRGBAPixel(red: 255, green: 0, blue: 0),
                GIFRGBAPixel(red: 0, green: 255, blue: 0),
                GIFRGBAPixel(red: 0, green: 0, blue: 255),
                GIFRGBAPixel(red: 255, green: 255, blue: 255)
            ]
        )

        let palette = try MedianCutPaletteBuilder().palette(from: [frame], maxColorCount: 4)

        #expect(
            Set(palette.colors) == [
                GIFPaletteColor(red: 0, green: 0, blue: 255),
                GIFPaletteColor(red: 0, green: 255, blue: 0),
                GIFPaletteColor(red: 255, green: 0, blue: 0),
                GIFPaletteColor(red: 255, green: 255, blue: 255)
            ])
    }

    @Test("median cut palette ignores transparent pixels when requested")
    func medianCutPaletteIgnoresTransparentPixelsWhenRequested() throws {
        let frame = try GIFFrameBitmap(
            pixelSize: PixelSize(width: 2, height: 1),
            pixels: [
                GIFRGBAPixel(red: 255, green: 0, blue: 0, alpha: 0),
                GIFRGBAPixel(red: 0, green: 255, blue: 0, alpha: 255)
            ]
        )

        let palette = try MedianCutPaletteBuilder().palette(
            from: [frame],
            maxColorCount: 2,
            transparentAlphaThreshold: 128
        )

        #expect(palette.colors.contains(GIFPaletteColor(red: 0, green: 255, blue: 0)))
        #expect(!palette.colors.contains(GIFPaletteColor(red: 255, green: 0, blue: 0)))
    }

    @Test("median cut palette caps output and is deterministic")
    func medianCutPaletteCapsOutputAndIsDeterministic() throws {
        var pixels: [GIFRGBAPixel] = []
        for value in 0..<16 {
            pixels.append(
                GIFRGBAPixel(
                    red: UInt8(value * 16),
                    green: UInt8(255 - value * 12),
                    blue: UInt8(value * 8)
                ))
        }
        let frame = try GIFFrameBitmap(
            pixelSize: PixelSize(width: 4, height: 4),
            pixels: pixels
        )
        let builder = MedianCutPaletteBuilder()

        let first = try builder.palette(from: [frame], maxColorCount: 4)
        let second = try builder.palette(from: [frame], maxColorCount: 4)

        #expect(first.colors.count == 4)
        #expect(first == second)
    }

    @Test("palette pads single colors and finds nearest indexes")
    func palettePadsSingleColorsAndFindsNearestIndexes() throws {
        let frame = try solidBitmap(
            width: 2, height: 2, color: GIFRGBAPixel(red: 10, green: 20, blue: 30))

        let palette = try MedianCutPaletteBuilder().palette(from: [frame], maxColorCount: 8)
        let nearest = palette.nearestColorIndex(for: GIFRGBAPixel(red: 12, green: 19, blue: 28))

        #expect(
            palette.colors == [
                GIFPaletteColor(red: 0, green: 0, blue: 0),
                GIFPaletteColor(red: 10, green: 20, blue: 30)
            ])
        #expect(nearest == 1)
    }

    @Test("palette builder validates inputs")
    func paletteBuilderValidatesInputs() throws {
        let frame = try solidBitmap(width: 1, height: 1, color: GIFRGBAPixel(red: 0, green: 0, blue: 0))

        #expect(throws: GIFEngineModelError.invalidFrameCount) {
            _ = try MedianCutPaletteBuilder().palette(from: [], maxColorCount: 4)
        }
        #expect(throws: GIFEngineModelError.invalidPaletteSize) {
            _ = try MedianCutPaletteBuilder().palette(from: [frame], maxColorCount: 1)
        }
        #expect(throws: GIFEngineModelError.invalidPaletteSize) {
            _ = try MedianCutPaletteBuilder().palette(from: [frame], maxColorCount: 257)
        }
        #expect(throws: GIFEngineModelError.invalidPaletteSize) {
            _ = try GIFColorPalette(colors: [GIFPaletteColor(red: 0, green: 0, blue: 0)])
        }
    }

    @Test("nearest color quantizer maps pixels to palette indexes")
    func nearestColorQuantizerMapsPixelsToPaletteIndexes() throws {
        let palette = try blackWhitePalette()
        let frame = try GIFFrameBitmap(
            pixelSize: PixelSize(width: 2, height: 1),
            pixels: [
                GIFRGBAPixel(red: 10, green: 10, blue: 10),
                GIFRGBAPixel(red: 240, green: 240, blue: 240)
            ]
        )

        let indexed = try GIFNearestColorQuantizer().indexedFrame(from: frame, palette: palette)

        #expect(indexed.colorIndexes == [0, 1])
    }

    @Test("ordered ditherer emits stable Bayer pattern")
    func orderedDithererEmitsStableBayerPattern() throws {
        let palette = try blackWhitePalette()
        let frame = try solidBitmap(
            width: 4, height: 4, color: GIFRGBAPixel(red: 128, green: 128, blue: 128))

        let indexed = try OrderedDitherer().indexedFrame(from: frame, palette: palette)

        #expect(
            indexed.colorIndexes == [
                0, 1, 0, 1,
                1, 0, 1, 0,
                0, 1, 0, 1,
                1, 0, 1, 0
            ])
    }

    @Test("floyd steinberg ditherer diffuses quantization error")
    func floydSteinbergDithererDiffusesQuantizationError() throws {
        let palette = try blackWhitePalette()
        let frame = try solidBitmap(
            width: 3,
            height: 1,
            color: GIFRGBAPixel(red: 96, green: 96, blue: 96)
        )

        let indexed = try FloydSteinbergDitherer().indexedFrame(from: frame, palette: palette)

        #expect(indexed.colorIndexes == [0, 1, 0])
    }
}
