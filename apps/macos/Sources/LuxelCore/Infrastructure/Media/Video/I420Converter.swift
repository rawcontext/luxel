import Accelerate
import CoreVideo
import Foundation

public struct I420Converter: Sendable {
    public init() {}

    public func convertBGRA(
        data bgraData: Data,
        pixelSize: PixelSize,
        bytesPerRow: Int? = nil
    ) throws -> I420Frame {
        let sourceBytesPerRow = bytesPerRow ?? pixelSize.width * 4
        try validate(pixelSize: pixelSize, bytesPerRow: sourceBytesPerRow)

        let minimumByteCount = sourceBytesPerRow * (pixelSize.height - 1) + pixelSize.width * 4
        guard bgraData.count >= minimumByteCount else {
            throw I420ConverterError.invalidSourceBuffer
        }

        return try bgraData.withUnsafeBytes { sourcePointer in
            guard let baseAddress = sourcePointer.baseAddress else {
                throw I420ConverterError.invalidSourceBuffer
            }

            return try convertBGRA(
                baseAddress: baseAddress,
                pixelSize: pixelSize,
                bytesPerRow: sourceBytesPerRow
            )
        }
    }

    public func convertBGRA(pixelBuffer: CVPixelBuffer) throws -> I420Frame {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA else {
            throw I420ConverterError.unsupportedPixelFormat
        }

        let lockStatus = CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        guard lockStatus == kCVReturnSuccess else {
            throw I420ConverterError.pixelBufferLockFailed(lockStatus)
        }
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw I420ConverterError.invalidSourceBuffer
        }

        return try convertBGRA(
            baseAddress: baseAddress,
            pixelSize: PixelSize(
                width: CVPixelBufferGetWidth(pixelBuffer),
                height: CVPixelBufferGetHeight(pixelBuffer)
            ),
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer)
        )
    }

    private func convertBGRA(
        baseAddress: UnsafeRawPointer,
        pixelSize: PixelSize,
        bytesPerRow: Int
    ) throws -> I420Frame {
        try validate(pixelSize: pixelSize, bytesPerRow: bytesPerRow)

        var yPlane = Data(count: pixelSize.width * pixelSize.height)
        var uPlane = Data(count: (pixelSize.width / 2) * (pixelSize.height / 2))
        var vPlane = Data(count: (pixelSize.width / 2) * (pixelSize.height / 2))
        var conversionInfo = try Self.bt709LimitedConversionInfo.get()
        var permuteMap: [UInt8] = [3, 2, 1, 0]
        var conversionError: vImage_Error = kvImageNoError

        yPlane.withUnsafeMutableBytes { yPointer in
            uPlane.withUnsafeMutableBytes { uPointer in
                vPlane.withUnsafeMutableBytes { vPointer in
                    var sourceBuffer = vImage_Buffer(
                        data: UnsafeMutableRawPointer(mutating: baseAddress),
                        height: vImagePixelCount(pixelSize.height),
                        width: vImagePixelCount(pixelSize.width),
                        rowBytes: bytesPerRow
                    )
                    var yBuffer = vImage_Buffer(
                        data: yPointer.baseAddress,
                        height: vImagePixelCount(pixelSize.height),
                        width: vImagePixelCount(pixelSize.width),
                        rowBytes: pixelSize.width
                    )
                    var uBuffer = vImage_Buffer(
                        data: uPointer.baseAddress,
                        height: vImagePixelCount(pixelSize.height / 2),
                        width: vImagePixelCount(pixelSize.width / 2),
                        rowBytes: pixelSize.width / 2
                    )
                    var vBuffer = vImage_Buffer(
                        data: vPointer.baseAddress,
                        height: vImagePixelCount(pixelSize.height / 2),
                        width: vImagePixelCount(pixelSize.width / 2),
                        rowBytes: pixelSize.width / 2
                    )

                    conversionError = vImageConvert_ARGB8888To420Yp8_Cb8_Cr8(
                        &sourceBuffer,
                        &yBuffer,
                        &uBuffer,
                        &vBuffer,
                        &conversionInfo,
                        &permuteMap,
                        vImage_Flags(kvImageNoFlags)
                    )
                }
            }
        }

        guard conversionError == kvImageNoError else {
            throw I420ConverterError.conversionFailed(conversionError)
        }

        return try I420Frame(pixelSize: pixelSize, yPlane: yPlane, uPlane: uPlane, vPlane: vPlane)
    }

    private func validate(pixelSize: PixelSize, bytesPerRow: Int) throws {
        guard pixelSize.width.isMultiple(of: 2),
              pixelSize.height.isMultiple(of: 2),
              bytesPerRow >= pixelSize.width * 4
        else {
            throw I420ConverterError.invalidPixelSize
        }
    }

    private static let bt709LimitedConversionInfo = Result {
        try makeBT709LimitedConversionInfo()
    }

    private static func makeBT709LimitedConversionInfo() throws -> vImage_ARGBToYpCbCr {
        var pixelRange = vImage_YpCbCrPixelRange(
            Yp_bias: 16,
            CbCr_bias: 128,
            YpRangeMax: 235,
            CbCrRangeMax: 240,
            YpMax: 235,
            YpMin: 16,
            CbCrMax: 240,
            CbCrMin: 16
        )
        var conversionInfo = vImage_ARGBToYpCbCr()
        var matrix = vImage_ARGBToYpCbCrMatrix(
            R_Yp: 0.2126,
            G_Yp: 0.7152,
            B_Yp: 0.0722,
            R_Cb: -0.11457210605733996,
            G_Cb: -0.38542789394266,
            B_Cb_R_Cr: 0.5,
            G_Cr: -0.45415290830581656,
            B_Cr: -0.04584709169418339
        )
        let error = vImageConvert_ARGBToYpCbCr_GenerateConversion(
            &matrix,
            &pixelRange,
            &conversionInfo,
            kvImageARGB8888,
            kvImage420Yp8_Cb8_Cr8,
            vImage_Flags(kvImageNoFlags)
        )

        guard error == kvImageNoError else {
            throw I420ConverterError.conversionFailed(error)
        }

        return conversionInfo
    }
}

public enum I420ConverterError: Error, Equatable {
    case invalidPixelSize
    case invalidSourceBuffer
    case unsupportedPixelFormat
    case pixelBufferLockFailed(CVReturn)
    case conversionFailed(vImage_Error)
}
