import Foundation

struct NativeGIFEncoder: Sendable {
    private let transparentColorIndex = UInt8(0)

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
            maxColorCount: min(options.paletteSize, 255)
        )
        let palette = try GIFColorPalette(colors: [
            GIFPaletteColor(red: 0, green: 0, blue: 0)
        ] + sourcePalette.colors)
        let indexedFrames = try GIFFrameIndexer()
            .indexedFrames(
                from: frames,
                palette: sourcePalette,
                dithering: options.dithering
            )
            .map(shiftedIndexedFrame)
        let deltas = try frameDeltas(
            bitmaps: frames,
            indexedFrames: indexedFrames,
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
        var previousFrame: GIFFrameBitmap?
        var deltas: [GIFFrameDelta] = []
        deltas.reserveCapacity(bitmaps.count)

        for (bitmap, indexedFrame) in zip(bitmaps, indexedFrames) {
            deltas.append(try differ.delta(
                from: previousFrame,
                to: bitmap,
                indexedFrame: indexedFrame,
                transparentColorIndex: transparentColorIndex,
                lossyTolerance: lossyTolerance
            ))
            previousFrame = bitmap
        }

        return deltas
    }

    private func shiftedIndexedFrame(_ frame: GIFIndexedFrame) throws -> GIFIndexedFrame {
        try GIFIndexedFrame(
            pixelSize: frame.pixelSize,
            colorIndexes: frame.colorIndexes.map { $0 + 1 }
        )
    }
}
