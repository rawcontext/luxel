import CoreGraphics
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import ImageIO
import LuxelCore
import Testing

extension CameraCutoutPipelineTests {
    func portraitImage(
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

    var vendoredModelURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "Vendor/Models/modnet/MODNetPortraitMatting.mlmodelc")
    }

    func makeCameraBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        try makeBGRABuffer(width: width, height: height) { columnIndex in
            BGRAPixel(
                blue: columnIndex < width / 2 ? 32 : 220,
                green: 96,
                red: columnIndex < width / 2 ? 220 : 32,
                alpha: 255
            )
        }
    }

    func makePortraitFixtureBuffer() throws -> CVPixelBuffer {
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

    func alphaStatistics(
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

    func makeGreenScreenBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        try makeBGRABuffer(width: width, height: height) { columnIndex in
            let isGreen = columnIndex < width / 2
            return BGRAPixel(
                blue: isGreen ? 0 : 32,
                green: isGreen ? 255 : 48,
                red: isGreen ? 0 : 224,
                alpha: 255
            )
        }
    }

    func makeBGRABuffer(
        width: Int,
        height: Int,
        pixel: (Int) -> BGRAPixel
    ) throws -> CVPixelBuffer {
        let buffer = try makePixelBuffer(
            width: width,
            height: height,
            pixelFormat: kCVPixelFormatType_32BGRA
        )
        try withLockedBaseAddress(of: buffer) { baseAddress, bytesPerRow in
            for rowIndex in 0..<height {
                let row =
                    baseAddress
                    .advanced(by: rowIndex * bytesPerRow)
                    .assumingMemoryBound(to: UInt8.self)
                for columnIndex in 0..<width {
                    let offset = columnIndex * 4
                    let color = pixel(columnIndex)
                    row[offset] = color.blue
                    row[offset + 1] = color.green
                    row[offset + 2] = color.red
                    row[offset + 3] = color.alpha
                }
            }
        }
        return buffer
    }

    func makeMatteBuffer(
        width: Int,
        height: Int,
        value: (Int, Int) -> Float
    ) throws -> CVPixelBuffer {
        let buffer = try makePixelBuffer(
            width: width,
            height: height,
            pixelFormat: kCVPixelFormatType_OneComponent16Half
        )
        try withLockedBaseAddress(of: buffer) { baseAddress, bytesPerRow in
            for rowIndex in 0..<height {
                let row =
                    baseAddress
                    .advanced(by: rowIndex * bytesPerRow)
                    .assumingMemoryBound(to: UInt16.self)
                for columnIndex in 0..<width {
                    row[columnIndex] = Float16(value(columnIndex, rowIndex)).bitPattern
                }
            }
        }
        return buffer
    }

    func withLockedBaseAddress(
        of buffer: CVPixelBuffer,
        write: (UnsafeMutableRawPointer, Int) -> Void
    ) throws {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else {
            throw FixtureError.missingBaseAddress
        }
        write(baseAddress, CVPixelBufferGetBytesPerRow(buffer))
    }

    func makePixelBuffer(
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

    func rgbaPixels(_ image: CGImage) throws -> [UInt8] {
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

    func alpha(
        _ pixels: [UInt8],
        x columnIndex: Int,
        y rowIndex: Int,
        width: Int
    ) -> UInt8 {
        pixels[(rowIndex * width + columnIndex) * 4 + 3]
    }

    func rgba(
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

struct BGRAPixel {
    let blue: UInt8
    let green: UInt8
    let red: UInt8
    let alpha: UInt8
}

struct MatteStatistics {
    let minimum: Float
    let maximum: Float
    let foregroundCoverage: Double
}

struct RGBA {
    let red: UInt8
    let green: UInt8
    let blue: UInt8
    let alpha: UInt8
}

enum FixtureError: Error {
    case cannotCreatePixelBuffer(CVReturn)
    case missingBaseAddress
    case cannotCreateContext
    case missingPortraitFixture
    case invalidPortraitFixture
}
