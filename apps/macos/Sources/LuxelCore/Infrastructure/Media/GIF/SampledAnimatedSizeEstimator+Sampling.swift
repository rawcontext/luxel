import AVFoundation
import CoreGraphics

extension SampledAnimatedSizeEstimator {
    func sampledImageIOFrames(
        at indices: [Int],
        context: SampledAnimatedImageIOContext
    ) async throws -> ([CGImage], [Int]) {
        var frames: [CGImage] = []
        var byteCounts: [Int] = []
        for index in indices {
            try Task.checkCancellation()
            let frame = try await renderedFrame(
                atFrameIndex: index,
                request: context.request,
                outputPixelSize: context.outputPixelSize,
                schedule: context.schedule,
                imageGenerator: context.imageGenerator
            )
            frames.append(frame)
            byteCounts.append(
                try encodedByteCount(
                    frames: [frame],
                    format: context.request.format,
                    frameDelay: context.schedule.frameDelay,
                    loopMode: context.loopMode
                ))
        }
        return (frames, byteCounts)
    }

    func sampledGIFFrames(
        at indices: [Int],
        context: SampledAnimatedGIFContext
    ) async throws -> ([GIFFrameBitmap], [Int]) {
        var frames: [GIFFrameBitmap] = []
        var byteCounts: [Int] = []
        for index in indices {
            try Task.checkCancellation()
            let frame = try await renderedGIFFrame(
                atFrameIndex: index,
                request: context.request,
                outputPixelSize: context.outputPixelSize,
                schedule: context.schedule,
                backgroundMatte: context.options.backgroundMatte,
                imageGenerator: context.imageGenerator
            )
            frames.append(frame)
            byteCounts.append(
                try gifEncodedByteCount(
                    frames: [frame],
                    outputPixelSize: context.outputPixelSize,
                    frameDelay: context.schedule.frameDelay,
                    options: context.options,
                    encoder: context.encoder
                ))
        }
        return (frames, byteCounts)
    }
}

struct SampledAnimatedImageIOContext {
    let request: ExportRequest
    let outputPixelSize: PixelSize
    let schedule: AnimatedFrameSchedule
    let imageGenerator: AVAssetImageGenerator
    let loopMode: GIFLoopMode
}

struct SampledAnimatedGIFContext {
    let request: ExportRequest
    let outputPixelSize: PixelSize
    let schedule: AnimatedFrameSchedule
    let imageGenerator: AVAssetImageGenerator
    let options: GIFRenderOptions
    let encoder: NativeGIFEncoder
}
