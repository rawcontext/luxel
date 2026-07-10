import CoreGraphics
import CoreImage
import CoreMedia
import CoreVideo
import Foundation

public enum CameraCutoutCompositorError: Error, Equatable {
    case invalidOutputSize
    case cannotCreateImage
}

public final class CameraCutoutCompositor: @unchecked Sendable {
    private let lock = NSLock()
    private let context: CIContext
    private var previousMatte: CVPixelBuffer?
    private var previousCoverage: Float?
    private var previousTimestamp: CMTime?
    private var previousGeneration: UInt64?

    public init() {
        context = CIContext(options: [.cacheIntermediates: false])
    }

    public func composite(
        cameraFrame: CVPixelBuffer,
        alphaMatte: CVPixelBuffer,
        outputSize: CGSize,
        isMirrored: Bool,
        timestamp: CMTime,
        generation: UInt64
    ) throws -> CGImage {
        try lock.withLock {
            try compositeLocked(
                cameraFrame: cameraFrame,
                alphaMatte: alphaMatte,
                outputSize: outputSize,
                isMirrored: isMirrored,
                timestamp: timestamp,
                generation: generation
            )
        }
    }

    private func compositeLocked(
        cameraFrame: CVPixelBuffer,
        alphaMatte: CVPixelBuffer,
        outputSize: CGSize,
        isMirrored: Bool,
        timestamp: CMTime,
        generation: UInt64
    ) throws -> CGImage {
        guard outputSize.width > 0, outputSize.height > 0 else {
            throw CameraCutoutCompositorError.invalidOutputSize
        }

        let outputExtent = CGRect(origin: .zero, size: outputSize)
        let cameraImage = Self.squareImage(
            CIImage(cvPixelBuffer: cameraFrame),
            outputExtent: outputExtent
        )
        let matteImage = stabilizedMatte(
            alphaMatte,
            outputExtent: outputExtent,
            timestamp: timestamp,
            generation: generation
        )
        let transparent = CIImage(color: .clear).cropped(to: outputExtent)
        var composite = cameraImage.applyingFilter(
            "CIBlendWithMask",
            parameters: [
                kCIInputBackgroundImageKey: transparent,
                kCIInputMaskImageKey: matteImage
            ]
        )
        if isMirrored {
            composite = composite.transformed(
                by: CGAffineTransform(translationX: outputExtent.width, y: 0)
                    .scaledBy(x: -1, y: 1)
            )
        }

        guard
            let image = context.createCGImage(
                composite,
                from: outputExtent,
                format: .BGRA8,
                colorSpace: Self.colorSpace
            )
        else {
            throw CameraCutoutCompositorError.cannotCreateImage
        }
        return image
    }

    public func reset() {
        lock.withLock {
            previousMatte = nil
            previousCoverage = nil
            previousTimestamp = nil
            previousGeneration = nil
        }
    }

    private func stabilizedMatte(
        _ matte: CVPixelBuffer,
        outputExtent: CGRect,
        timestamp: CMTime,
        generation: UInt64
    ) -> CIImage {
        let currentCoverage = Self.coverage(of: matte)
        let current = Self.squareImage(CIImage(cvPixelBuffer: matte), outputExtent: outputExtent)
        let shouldReset = previousGeneration != generation
            || previousTimestamp.map { timestamp.seconds - $0.seconds > Self.maximumFrameGap } ?? true
            || previousCoverage.map { abs(currentCoverage - $0) > Self.maximumCoverageDelta } ?? true

        defer {
            previousMatte = matte
            previousCoverage = currentCoverage
            previousTimestamp = timestamp
            previousGeneration = generation
        }

        guard !shouldReset, let previousMatte else {
            return current
        }

        let previous = Self.squareImage(
            CIImage(cvPixelBuffer: previousMatte),
            outputExtent: outputExtent
        )
        return current.applyingFilter(
            "CIDissolveTransition",
            parameters: [
                kCIInputTargetImageKey: previous,
                kCIInputTimeKey: Self.previousMatteWeight
            ]
        )
    }

    private static func squareImage(_ image: CIImage, outputExtent: CGRect) -> CIImage {
        let square = MODNetPortraitMattingProcessor.centerCroppedImage(image)
        let translated = square.transformed(
            by: CGAffineTransform(translationX: -square.extent.minX, y: -square.extent.minY)
        )
        let scaleX = outputExtent.width / square.extent.width
        let scaleY = outputExtent.height / square.extent.height
        return translated
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .cropped(to: outputExtent)
    }

    private static func coverage(of matte: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(matte, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(matte, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(matte) else {
            return 0
        }

        let width = CVPixelBufferGetWidth(matte)
        let height = CVPixelBufferGetHeight(matte)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(matte)
        var total: Float = 0
        var count: Float = 0
        for rowIndex in stride(from: 0, to: height, by: 16) {
            let row = baseAddress
                .advanced(by: rowIndex * bytesPerRow)
                .assumingMemoryBound(to: UInt16.self)
            for columnIndex in stride(from: 0, to: width, by: 16) {
                total += Float(Float16(bitPattern: row[columnIndex]))
                count += 1
            }
        }
        return count > 0 ? total / count : 0
    }

    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let previousMatteWeight = 0.28
    private static let maximumFrameGap = 0.25
    private static let maximumCoverageDelta: Float = 0.2
}
