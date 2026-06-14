import CoreVideo
import Foundation
import LuxelCore
import Testing

@Suite("I420 converter")
struct I420ConverterTests {
    @Test("converts BGRA data to BT.709 limited I420 planes")
    func convertsBGRADataToBT709LimitedI420Planes() throws {
        let converter = I420Converter()
        let black = try converter.convertBGRA(
            data: solidBGRA(blue: 0, green: 0, red: 0),
            pixelSize: PixelSize(width: 2, height: 2)
        )
        let white = try converter.convertBGRA(
            data: solidBGRA(blue: 255, green: 255, red: 255),
            pixelSize: PixelSize(width: 2, height: 2)
        )
        let red = try converter.convertBGRA(
            data: solidBGRA(blue: 0, green: 0, red: 255),
            pixelSize: PixelSize(width: 2, height: 2)
        )

        #expect(Array(black.yPlane) == [16, 16, 16, 16])
        #expect(Array(black.uPlane) == [128])
        #expect(Array(black.vPlane) == [128])
        #expect(Array(white.yPlane) == [235, 235, 235, 235])
        #expect(Array(white.uPlane) == [128])
        #expect(Array(white.vPlane) == [128])
        #expect(Array(red.yPlane) == [63, 63, 63, 63])
        #expect(Array(red.uPlane) == [102])
        #expect(Array(red.vPlane) == [240])
    }

    @Test("honors BGRA source row padding")
    func honorsBGRASourceRowPadding() throws {
        let converter = I420Converter()
        let rowStride = 12
        let paddedBGRA = Data([
            0, 0, 255, 255, 0, 255, 0, 255, 99, 99, 99, 99,
            255, 0, 0, 255, 255, 255, 255, 255, 99, 99, 99, 99
        ])

        let frame = try converter.convertBGRA(
            data: paddedBGRA,
            pixelSize: PixelSize(width: 2, height: 2),
            bytesPerRow: rowStride
        )

        #expect(Array(frame.yPlane) == [63, 173, 32, 235])
        #expect(Array(frame.uPlane) == [128])
        #expect(Array(frame.vPlane) == [128])
    }

    @Test("converts BGRA pixel buffers")
    func convertsBGRAPixelBuffers() throws {
        let pixelBuffer = try makePixelBuffer(pixelFormat: kCVPixelFormatType_32BGRA)
        try fill(pixelBuffer, bgraPixel: [0, 0, 255, 255])

        let frame = try I420Converter().convertBGRA(pixelBuffer: pixelBuffer)

        #expect(Array(frame.yPlane) == [63, 63, 63, 63])
        #expect(Array(frame.uPlane) == [102])
        #expect(Array(frame.vPlane) == [240])
    }

    @Test("rejects invalid source shape and pixel format")
    func rejectsInvalidSourceShapeAndPixelFormat() throws {
        let converter = I420Converter()

        #expect(throws: I420ConverterError.invalidPixelSize) {
            _ = try converter.convertBGRA(
                data: Data(repeating: 0, count: 3 * 2 * 4),
                pixelSize: PixelSize(width: 3, height: 2)
            )
        }

        #expect(throws: I420ConverterError.invalidSourceBuffer) {
            _ = try converter.convertBGRA(
                data: Data(repeating: 0, count: 7),
                pixelSize: PixelSize(width: 2, height: 2)
            )
        }

        let argbPixelBuffer = try makePixelBuffer(pixelFormat: kCVPixelFormatType_32ARGB)
        #expect(throws: I420ConverterError.unsupportedPixelFormat) {
            _ = try converter.convertBGRA(pixelBuffer: argbPixelBuffer)
        }
    }

    private func solidBGRA(blue: UInt8, green: UInt8, red: UInt8) -> Data {
        Data(Array(repeating: [blue, green, red, 255], count: 4).flatMap { $0 })
    }

    private func makePixelBuffer(pixelFormat: OSType) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            2,
            2,
            pixelFormat,
            nil,
            &pixelBuffer
        )

        #expect(status == kCVReturnSuccess)
        return try #require(pixelBuffer)
    }

    private func fill(_ pixelBuffer: CVPixelBuffer, bgraPixel: [UInt8]) throws {
        #expect(bgraPixel.count == 4)

        let lockStatus = CVPixelBufferLockBaseAddress(pixelBuffer, [])
        #expect(lockStatus == kCVReturnSuccess)
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        }

        let rowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let baseAddress = try #require(CVPixelBufferGetBaseAddress(pixelBuffer))
            .assumingMemoryBound(to: UInt8.self)

        for y in 0..<height {
            let row = baseAddress.advanced(by: y * rowBytes)
            for x in 0..<width {
                let pixel = row.advanced(by: x * 4)
                pixel[0] = bgraPixel[0]
                pixel[1] = bgraPixel[1]
                pixel[2] = bgraPixel[2]
                pixel[3] = bgraPixel[3]
            }
        }
    }
}
