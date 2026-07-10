import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
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
        let matte = try processor.alphaMatte(for: cameraFrame)

        #expect(processor.isPrepared)
        #expect(CVPixelBufferGetWidth(matte) == 512)
        #expect(CVPixelBufferGetHeight(matte) == 512)
        #expect(CVPixelBufferGetPixelFormatType(matte) == kCVPixelFormatType_OneComponent16Half)
    }

    @Test("composition preserves transparent mask geometry and mirrors RGB with alpha")
    func compositionPreservesMaskAndMirrorsCompletedImage() throws {
        let compositor = CameraCutoutCompositor()
        let cameraFrame = try makeCameraBuffer(width: 32, height: 32)
        let leftMask = try makeMatteBuffer(width: 32, height: 32) { columnIndex, _ in
            columnIndex < 16 ? 1 : 0
        }

        let unmirrored = try compositor.composite(
            cameraFrame: cameraFrame,
            alphaMatte: leftMask,
            outputSize: CGSize(width: 32, height: 32),
            isMirrored: false,
            timestamp: .zero,
            generation: 1
        )
        compositor.reset()
        let mirrored = try compositor.composite(
            cameraFrame: cameraFrame,
            alphaMatte: leftMask,
            outputSize: CGSize(width: 32, height: 32),
            isMirrored: true,
            timestamp: .zero,
            generation: 2
        )

        let unmirroredPixels = try rgbaPixels(unmirrored)
        let mirroredPixels = try rgbaPixels(mirrored)
        #expect(alpha(unmirroredPixels, x: 4, y: 16, width: 32) > 250)
        #expect(alpha(unmirroredPixels, x: 27, y: 16, width: 32) < 5)
        #expect(alpha(mirroredPixels, x: 4, y: 16, width: 32) < 5)
        #expect(alpha(mirroredPixels, x: 27, y: 16, width: 32) > 250)
    }

    @Test("temporal matte blending reduces flicker and resets for a new generation")
    func temporalMatteBlendingReducesFlickerAndResets() throws {
        let compositor = CameraCutoutCompositor()
        let cameraFrame = try makeCameraBuffer(width: 32, height: 32)
        let leftMask = try makeMatteBuffer(width: 32, height: 32) { columnIndex, _ in
            columnIndex < 16 ? 1 : 0
        }
        let rightMask = try makeMatteBuffer(width: 32, height: 32) { columnIndex, _ in
            columnIndex >= 16 ? 1 : 0
        }
        _ = try compositor.composite(
            cameraFrame: cameraFrame,
            alphaMatte: leftMask,
            outputSize: CGSize(width: 32, height: 32),
            isMirrored: false,
            timestamp: .zero,
            generation: 1
        )
        let blended = try compositor.composite(
            cameraFrame: cameraFrame,
            alphaMatte: rightMask,
            outputSize: CGSize(width: 32, height: 32),
            isMirrored: false,
            timestamp: CMTime(value: 1, timescale: 30),
            generation: 1
        )
        let reset = try compositor.composite(
            cameraFrame: cameraFrame,
            alphaMatte: rightMask,
            outputSize: CGSize(width: 32, height: 32),
            isMirrored: false,
            timestamp: CMTime(value: 2, timescale: 30),
            generation: 2
        )

        let blendedPixels = try rgbaPixels(blended)
        let resetPixels = try rgbaPixels(reset)
        let blendedLeft = alpha(blendedPixels, x: 4, y: 16, width: 32)
        let blendedRight = alpha(blendedPixels, x: 27, y: 16, width: 32)
        #expect((40...220).contains(blendedLeft))
        #expect((40...220).contains(blendedRight))
        #expect(alpha(resetPixels, x: 4, y: 16, width: 32) < 5)
        #expect(alpha(resetPixels, x: 27, y: 16, width: 32) > 250)
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
            let row = baseAddress
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
            let row = baseAddress
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
}

private enum FixtureError: Error {
    case cannotCreatePixelBuffer(CVReturn)
    case missingBaseAddress
    case cannotCreateContext
}
