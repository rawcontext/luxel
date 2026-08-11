import CoreGraphics
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import ImageIO
import LuxelCore
import Testing

@Suite("Camera Cutout image pipeline")
struct CameraCutoutPipelineTests {
    @Test("missing model fails preparation")
    func missingModelFailsPreparation() {
        let processor = MODNetPortraitMattingProcessor(modelURL: nil)

        #expect(throws: MODNetPortraitMattingError.missingModel) {
            try processor.prepare()
        }
    }

    @Test("vendored model prewarms and produces a finite 512 square alpha matte")
    func vendoredModelPrewarmsAndProducesAlphaMatte() throws {
        let processor = MODNetPortraitMattingProcessor(modelURL: vendoredModelURL)
        let cameraFrame = try makeCameraBuffer(width: 640, height: 480)

        try processor.prepare()
        let mattes = try (0..<4).map { _ in
            try processor.alphaMatte(for: cameraFrame)
        }
        let matte = mattes[0]

        #expect(processor.isPrepared)
        #expect(CVPixelBufferGetWidth(matte) == 512)
        #expect(CVPixelBufferGetHeight(matte) == 512)
        #expect(CVPixelBufferGetPixelFormatType(matte) == kCVPixelFormatType_OneComponent16Half)
        #expect(CVPixelBufferGetIOSurface(matte) != nil)
        #expect(mattes[0] === mattes[3])
    }

    @Test("real portrait fixture produces a structured alpha matte")
    func realPortraitFixtureProducesStructuredAlphaMatte() throws {
        let processor = MODNetPortraitMattingProcessor(modelURL: vendoredModelURL)
        let cameraFrame = try makePortraitFixtureBuffer()

        try processor.prepare()
        let matte = try processor.alphaMatte(for: cameraFrame)
        let statistics = try alphaStatistics(matte)

        #expect(statistics.minimum < 0.1)
        #expect(statistics.maximum > 0.9)
        #expect((0.1...0.9).contains(statistics.foregroundCoverage))
    }

    @Test("composition preserves premultiplied color and mirrors RGB with alpha")
    func compositionPreservesPremultipliedColorAndMirrorsCompletedImage() throws {
        let compositor = CameraCutoutCompositor()
        let cameraFrame = try makeCameraBuffer(width: 32, height: 32)
        let leftMask = try makeMatteBuffer(width: 32, height: 32) { columnIndex, _ in
            columnIndex < 16 ? 0.5 : 0
        }

        let unmirrored = try portraitImage(
            compositor: compositor,
            cameraFrame: cameraFrame,
            matte: leftMask,
            isMirrored: false
        )
        compositor.reset()
        let mirrored = try portraitImage(
            compositor: compositor,
            cameraFrame: cameraFrame,
            matte: leftMask,
            isMirrored: true
        )

        let unmirroredPixels = try rgbaPixels(unmirrored.image)
        let mirroredPixels = try rgbaPixels(mirrored.image)
        let foreground = rgba(unmirroredPixels, x: 4, y: 16, width: 32)
        #expect((120...135).contains(foreground.alpha))
        #expect(foreground.red <= foreground.alpha)
        #expect(foreground.green <= foreground.alpha)
        #expect(foreground.blue <= foreground.alpha)
        #expect(alpha(unmirroredPixels, x: 27, y: 16, width: 32) < 5)
        #expect(alpha(mirroredPixels, x: 4, y: 16, width: 32) < 5)
        #expect((120...135).contains(alpha(mirroredPixels, x: 27, y: 16, width: 32)))
    }

    @Test("one frame delay corrects isolated flicker and resets on discontinuity")
    func oneFrameDelayCorrectsFlickerAndResets() throws {
        let compositor = CameraCutoutCompositor()
        let cameraFrame = try makeCameraBuffer(width: 32, height: 32)
        let leftMask = try makeMatteBuffer(width: 32, height: 32) { columnIndex, _ in
            columnIndex < 16 ? 1 : 0
        }
        let rightMask = try makeMatteBuffer(width: 32, height: 32) { columnIndex, _ in
            columnIndex >= 16 ? 1 : 0
        }
        #expect(
            try compositor.compositePortraitFrame(
                cameraFrame: cameraFrame,
                alphaMatte: leftMask,
                outputSize: CGSize(width: 32, height: 32),
                isMirrored: false,
                timestamp: CMTime(value: 0, timescale: 30),
                generation: 1
            ) == nil)
        #expect(
            try compositor.compositePortraitFrame(
                cameraFrame: cameraFrame,
                alphaMatte: rightMask,
                outputSize: CGSize(width: 32, height: 32),
                isMirrored: false,
                timestamp: CMTime(value: 1, timescale: 30),
                generation: 1
            ) != nil)
        let correctedCandidate = try compositor.compositePortraitFrame(
            cameraFrame: cameraFrame,
            alphaMatte: leftMask,
            outputSize: CGSize(width: 32, height: 32),
            isMirrored: false,
            timestamp: CMTime(value: 2, timescale: 30),
            generation: 1
        )
        let corrected = try #require(correctedCandidate)

        let correctedPixels = try rgbaPixels(corrected.image)
        #expect(alpha(correctedPixels, x: 4, y: 16, width: 32) > 250)
        #expect(alpha(correctedPixels, x: 27, y: 16, width: 32) < 5)

        #expect(
            try compositor.compositePortraitFrame(
                cameraFrame: cameraFrame,
                alphaMatte: rightMask,
                outputSize: CGSize(width: 32, height: 32),
                isMirrored: false,
                timestamp: CMTime(value: 0, timescale: 30),
                generation: 1
            ) == nil)
    }

    @Test("green screen key removes green and keeps foreground color")
    func greenScreenKeyRemovesGreenAndKeepsForeground() throws {
        let compositor = CameraCutoutCompositor()
        let cameraFrame = try makeGreenScreenBuffer(width: 32, height: 32)
        let candidate = try compositor.compositeGreenScreenFrame(
            cameraFrame: cameraFrame,
            outputSize: CGSize(width: 32, height: 32),
            isMirrored: false,
            timestamp: CMTime(value: 0, timescale: 30)
        )
        let image = try #require(candidate)
        let pixels = try rgbaPixels(image.image)
        let keyed = rgba(pixels, x: 4, y: 16, width: 32)
        let foreground = rgba(pixels, x: 27, y: 16, width: 32)

        #expect(keyed.alpha < 10)
        #expect(keyed.red <= keyed.alpha)
        #expect(keyed.green <= keyed.alpha)
        #expect(keyed.blue <= keyed.alpha)
        #expect(foreground.alpha > 245)
        #expect(foreground.red > foreground.green)
    }

    @Test("render output pool stays bounded and reuses released surfaces")
    func renderOutputPoolStaysBoundedAndReusesReleasedSurfaces() throws {
        let compositor = CameraCutoutCompositor()
        let cameraFrame = try makeGreenScreenBuffer(width: 32, height: 32)
        var frames: [CameraCutoutCompositedFrame?] = try (0..<3).map { frameIndex in
            try compositor.compositeGreenScreenFrame(
                cameraFrame: cameraFrame,
                outputSize: CGSize(width: 32, height: 32),
                isMirrored: false,
                timestamp: CMTime(value: CMTimeValue(frameIndex), timescale: 30)
            )
        }

        #expect(frames.allSatisfy { $0 != nil })
        #expect(
            try compositor.compositeGreenScreenFrame(
                cameraFrame: cameraFrame,
                outputSize: CGSize(width: 32, height: 32),
                isMirrored: false,
                timestamp: CMTime(value: 3, timescale: 30)
            ) == nil)

        frames[0] = nil
        #expect(
            try compositor.compositeGreenScreenFrame(
                cameraFrame: cameraFrame,
                outputSize: CGSize(width: 32, height: 32),
                isMirrored: false,
                timestamp: CMTime(value: 4, timescale: 30)
            ) != nil)
    }
}
