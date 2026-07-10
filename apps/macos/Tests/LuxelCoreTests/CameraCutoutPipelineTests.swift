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

private extension CameraCutoutPipelineTests {
    private func portraitImage(
        compositor: CameraCutoutCompositor,
        cameraFrame: CVPixelBuffer,
        matte: CVPixelBuffer,
        isMirrored: Bool
    ) throws -> CameraCutoutCompositedFrame {
        #expect(
            try compositor.compositePortraitFrame(
                cameraFrame: cameraFrame,
                alphaMatte: matte,
                outputSize: CGSize(width: 32, height: 32),
                isMirrored: isMirrored,
                timestamp: CMTime(value: 0, timescale: 30),
                generation: 1
            ) == nil)
        let candidate = try compositor.compositePortraitFrame(
            cameraFrame: cameraFrame,
            alphaMatte: matte,
            outputSize: CGSize(width: 32, height: 32),
            isMirrored: isMirrored,
            timestamp: CMTime(value: 1, timescale: 30),
            generation: 1
        )
        return try #require(candidate)
    }

    private var vendoredModelURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Vendor/Models/modnet/MODNetPortraitMatting.mlmodelc")
    }

    private func makeCameraBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        let buffer = try makePixelBuffer(
            width: width,
            height: height,
            pixelFormat: kCVPixelFormatType_32BGRA
        )
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            throw FixtureError.missingBaseAddress
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        for rowIndex in 0..<height {
            let row =
                baseAddress
                .advanced(by: rowIndex * bytesPerRow)
                .assumingMemoryBound(to: UInt8.self)
            for columnIndex in 0..<width {
                let offset = columnIndex * 4
                row[offset] = columnIndex < width / 2 ? 32 : 220
                row[offset + 1] = 96
                row[offset + 2] = columnIndex < width / 2 ? 220 : 32
                row[offset + 3] = 255
            }
        }
        return buffer
    }

    private func makePortraitFixtureBuffer() throws -> CVPixelBuffer {
        guard
            let fixtureURL = Bundle.module.url(
                forResource: "loral-ohara-portrait",
                withExtension: "jpg.base64"
            )
        else {
            throw FixtureError.missingPortraitFixture
        }
        let encoded = try String(contentsOf: fixtureURL, encoding: .utf8)
        guard let data = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters),
              let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else {
            throw FixtureError.invalidPortraitFixture
        }

        let buffer = try makePixelBuffer(
            width: image.width,
            height: image.height,
            pixelFormat: kCVPixelFormatType_32BGRA
        )
        CIContext(options: [.cacheIntermediates: false]).render(
            CIImage(cgImage: image),
            to: buffer,
            bounds: CGRect(x: 0, y: 0, width: image.width, height: image.height),
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!
        )
        return buffer
    }

    private func alphaStatistics(
        _ matte: CVPixelBuffer
    ) throws -> MatteStatistics {
        CVPixelBufferLockBaseAddress(matte, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(matte, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(matte) else {
            throw FixtureError.missingBaseAddress
        }

        var minimum: Float = 1
        var maximum: Float = 0
        var foregroundSampleCount = 0
        var sampleCount = 0
        let width = CVPixelBufferGetWidth(matte)
        let height = CVPixelBufferGetHeight(matte)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(matte)
        for rowIndex in stride(from: 0, to: height, by: 4) {
            let row =
                baseAddress
                .advanced(by: rowIndex * bytesPerRow)
                .assumingMemoryBound(to: UInt16.self)
            for columnIndex in stride(from: 0, to: width, by: 4) {
                let value = Float(Float16(bitPattern: row[columnIndex]))
                minimum = min(minimum, value)
                maximum = max(maximum, value)
                foregroundSampleCount += value >= 0.5 ? 1 : 0
                sampleCount += 1
            }
        }
        return MatteStatistics(
            minimum: minimum,
            maximum: maximum,
            foregroundCoverage: Double(foregroundSampleCount) / Double(sampleCount)
        )
    }

    private func makeGreenScreenBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        let buffer = try makePixelBuffer(
            width: width,
            height: height,
            pixelFormat: kCVPixelFormatType_32BGRA
        )
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            throw FixtureError.missingBaseAddress
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        for rowIndex in 0..<height {
            let row =
                baseAddress
                .advanced(by: rowIndex * bytesPerRow)
                .assumingMemoryBound(to: UInt8.self)
            for columnIndex in 0..<width {
                let offset = columnIndex * 4
                let isGreen = columnIndex < width / 2
                row[offset] = isGreen ? 0 : 32
                row[offset + 1] = isGreen ? 255 : 48
                row[offset + 2] = isGreen ? 0 : 224
                row[offset + 3] = 255
            }
        }
        return buffer
    }

    private func makeMatteBuffer(
        width: Int,
        height: Int,
        value: (Int, Int) -> Float
    ) throws -> CVPixelBuffer {
        let buffer = try makePixelBuffer(
            width: width,
            height: height,
            pixelFormat: kCVPixelFormatType_OneComponent16Half
        )
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            throw FixtureError.missingBaseAddress
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        for rowIndex in 0..<height {
            let row =
                baseAddress
                .advanced(by: rowIndex * bytesPerRow)
                .assumingMemoryBound(to: UInt16.self)
            for columnIndex in 0..<width {
                row[columnIndex] = Float16(value(columnIndex, rowIndex)).bitPattern
            }
        }
        return buffer
    }

    private func makePixelBuffer(
        width: Int,
        height: Int,
        pixelFormat: OSType
    ) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            pixelFormat,
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else {
            throw FixtureError.cannotCreatePixelBuffer(status)
        }
        return buffer
    }

    private func rgbaPixels(_ image: CGImage) throws -> [UInt8] {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let created = pixels.withUnsafeMutableBytes { bytes in
            guard
                let context = CGContext(
                    data: bytes.baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                        | CGBitmapInfo.byteOrder32Big.rawValue
                )
            else {
                return false
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard created else {
            throw FixtureError.cannotCreateContext
        }
        return pixels
    }

    private func alpha(
        _ pixels: [UInt8],
        x columnIndex: Int,
        y rowIndex: Int,
        width: Int
    ) -> UInt8 {
        pixels[(rowIndex * width + columnIndex) * 4 + 3]
    }

    private func rgba(
        _ pixels: [UInt8],
        x columnIndex: Int,
        y rowIndex: Int,
        width: Int
    ) -> RGBA {
        let offset = (rowIndex * width + columnIndex) * 4
        return RGBA(
            red: pixels[offset],
            green: pixels[offset + 1],
            blue: pixels[offset + 2],
            alpha: pixels[offset + 3]
        )
    }
}

private struct MatteStatistics {
    let minimum: Float
    let maximum: Float
    let foregroundCoverage: Double
}

private struct RGBA {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8
}

private enum FixtureError: Error {
    case cannotCreatePixelBuffer(CVReturn)
    case missingBaseAddress
    case cannotCreateContext
    case missingPortraitFixture
    case invalidPortraitFixture
}
