import Foundation

struct NativeGIFEncoder: Sendable {
    private let transparentColorIndex = UInt8(0)
    private let alphaTransparencyThreshold = UInt8(128)

    func sequencedFrames(
        from frames: [GIFFrameBitmap],
        loopMode: GIFLoopMode
    ) throws -> [GIFFrameBitmap] {
        let frameIndexes = try GIFFrameSequencePlanner()
            .frameIndexes(frameCount: frames.count, loopMode: loopMode)
        return frameIndexes.map { frames[$0] }
    }

    func data(
        pixelSize: PixelSize,
        frames: [GIFFrameBitmap],
        frameDelay: TimeInterval,
        options: GIFRenderOptions
    ) throws -> Data {
        let sourcePalette = try MedianCutPaletteBuilder().palette(
            from: frames,
            maxColorCount: min(options.paletteSize, 255),
            transparentAlphaThreshold: alphaTransparencyThreshold
        )
        let palette = try GIFColorPalette(
            colors: [
                GIFPaletteColor(red: 0, green: 0, blue: 0)
            ] + sourcePalette.colors)
        let indexedFrames = try GIFFrameIndexer()
            .indexedFrames(
                from: frames,
                palette: sourcePalette,
                dithering: options.dithering
            )
        let outputIndexedFrames = try GIFConcurrentMapper.map(count: frames.count) { index in
            try shiftedIndexedFrame(indexedFrames[index], transparencyFrom: frames[index])
        }
        let deltas = try frameDeltas(
            bitmaps: frames,
            indexedFrames: outputIndexedFrames,
            lossyTolerance: options.lossyTolerance
        )
        let delays = try CentisecondDelayPlanner().plan(
            frameCount: frames.count,
            frameDuration: frameDelay
        )

        return try GIFContainerWriter().data(
            pixelSize: pixelSize,
            palette: palette,
            frames: deltas,
            delays: delays,
            loopMode: options.loopMode
        )
    }

    private func frameDeltas(
        bitmaps: [GIFFrameBitmap],
        indexedFrames: [GIFIndexedFrame],
        lossyTolerance: Int
    ) throws -> [GIFFrameDelta] {
        let differ = GIFFrameDiffer()

        return try GIFConcurrentMapper.map(count: bitmaps.count) { index in
            try differ.delta(
                from: index > 0 ? bitmaps[index - 1] : nil,
                to: bitmaps[index],
                indexedFrame: indexedFrames[index],
                transparentColorIndex: transparentColorIndex,
                lossyTolerance: lossyTolerance
            )
        }
    }

    private func shiftedIndexedFrame(
        _ frame: GIFIndexedFrame,
        transparencyFrom bitmap: GIFFrameBitmap
    ) throws -> GIFIndexedFrame {
        guard frame.pixelSize == bitmap.pixelSize else {
            throw GIFEngineModelError.frameSizeMismatch
        }

        return try GIFIndexedFrame(
            pixelSize: frame.pixelSize,
            colorIndexes: zip(bitmap.pixels, frame.colorIndexes).map { pixel, colorIndex in
                pixel.alpha < alphaTransparencyThreshold ? transparentColorIndex : colorIndex + 1
            }
        )
    }
}
