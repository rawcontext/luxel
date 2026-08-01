import CoreGraphics
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

public enum CameraCutoutCompositorError: Error, Equatable {
    case invalidOutputSize
    case cannotCreateImage
    case cannotCreateOutputBuffer
    case invalidPremultipliedOutput
}

public final class CameraCutoutCompositedFrame: @unchecked Sendable {
    public let image: CGImage
    public let sourceTimestamp: CMTime
    fileprivate let outputBufferLease: CameraCutoutOutputBufferLease

    fileprivate init(
        image: CGImage,
        sourceTimestamp: CMTime,
        outputBufferLease: CameraCutoutOutputBufferLease
    ) {
        self.image = image
        self.sourceTimestamp = sourceTimestamp
        self.outputBufferLease = outputBufferLease
    }
}

public final class CameraCutoutCompositor: @unchecked Sendable {
    private struct PendingPortraitFrame {
        let cameraFrame: CVPixelBuffer
        let alphaMatte: CVPixelBuffer
        let timestamp: CMTime
        let generation: UInt64
    }

    private let lock = NSLock()
    private let context: CIContext
    private lazy var chromaKeyFilter = CameraChromaKeyFilter()
    private var previousMatte: CVPixelBuffer?
    private var pendingPortraitFrame: PendingPortraitFrame?
    private var outputBufferPool: CameraCutoutOutputBufferPool?

    public init() {
        context = CIContext(options: [.cacheIntermediates: false])
    }

    public func prepareGreenScreen() {
        lock.withLock {
            let extent = CGRect(x: 0, y: 0, width: 1, height: 1)
            let keyedImage = chromaKeyFilter.apply(
                to: CIImage(color: CIColor(red: 0, green: 1, blue: 0)).cropped(to: extent)
            )
            _ = context.createCGImage(
                keyedImage,
                from: extent,
                format: .BGRA8,
                colorSpace: Self.colorSpace
            )
        }
    }

    public func compositePortraitFrame(
        cameraFrame: CVPixelBuffer,
        alphaMatte: CVPixelBuffer,
        outputSize: CGSize,
        isMirrored: Bool,
        timestamp: CMTime,
        generation: UInt64 = 0
    ) throws -> CameraCutoutCompositedFrame? {
        try lock.withLock {
            guard outputSize.width > 0, outputSize.height > 0 else {
                throw CameraCutoutCompositorError.invalidOutputSize
            }

            let incoming = PendingPortraitFrame(
                cameraFrame: cameraFrame,
                alphaMatte: alphaMatte,
                timestamp: timestamp,
                generation: generation
            )
            guard let pendingPortraitFrame else {
                self.pendingPortraitFrame = incoming
                previousMatte = nil
                return nil
            }

            guard Self.isContinuous(pendingPortraitFrame, incoming) else {
                self.pendingPortraitFrame = incoming
                previousMatte = nil
                return nil
            }

            let currentMatte = Self.oneFrameDelayMatte(
                previous: previousMatte,
                current: pendingPortraitFrame.alphaMatte,
                next: incoming.alphaMatte
            )
            let image = try renderPortrait(
                cameraFrame: pendingPortraitFrame.cameraFrame,
                alphaMatte: currentMatte,
                outputSize: outputSize,
                isMirrored: isMirrored,
                sourceTimestamp: pendingPortraitFrame.timestamp
            )
            previousMatte = pendingPortraitFrame.alphaMatte
            self.pendingPortraitFrame = incoming
            return image
        }
    }

    public func compositeGreenScreenFrame(
        cameraFrame: CVPixelBuffer,
        outputSize: CGSize,
        isMirrored: Bool,
        timestamp: CMTime
    ) throws -> CameraCutoutCompositedFrame? {
        try lock.withLock {
            guard outputSize.width > 0, outputSize.height > 0 else {
                throw CameraCutoutCompositorError.invalidOutputSize
            }
            let outputExtent = CGRect(origin: .zero, size: outputSize)
            let cameraImage = Self.squareImage(
                CIImage(cvPixelBuffer: cameraFrame),
                outputExtent: outputExtent
            )
            return try makeImage(
                chromaKeyFilter.apply(to: cameraImage),
                outputExtent: outputExtent,
                isMirrored: isMirrored,
                sourceTimestamp: timestamp
            )
        }
    }

    public func reset() {
        lock.withLock {
            previousMatte = nil
            pendingPortraitFrame = nil
        }
    }

    private func renderPortrait(
        cameraFrame: CVPixelBuffer,
        alphaMatte: CIImage,
        outputSize: CGSize,
        isMirrored: Bool,
        sourceTimestamp: CMTime
    ) throws -> CameraCutoutCompositedFrame? {
        let outputExtent = CGRect(origin: .zero, size: outputSize)
        let cameraImage = Self.squareImage(
            CIImage(cvPixelBuffer: cameraFrame),
            outputExtent: outputExtent
        )
        let matteImage = Self.squareImage(alphaMatte, outputExtent: outputExtent)
        let transparent = CIImage(color: .clear).cropped(to: outputExtent)
        let composite = cameraImage.applyingFilter(
            "CIBlendWithMask",
            parameters: [
                kCIInputBackgroundImageKey: transparent,
                kCIInputMaskImageKey: matteImage
            ]
        )
        return try makeImage(
            composite,
            outputExtent: outputExtent,
            isMirrored: isMirrored,
            sourceTimestamp: sourceTimestamp
        )
    }

    private func makeImage(
        _ source: CIImage,
        outputExtent: CGRect,
        isMirrored: Bool,
        sourceTimestamp: CMTime
    ) throws -> CameraCutoutCompositedFrame? {
        let image =
            isMirrored
            ? source.transformed(
                by: CGAffineTransform(translationX: outputExtent.width, y: 0)
                    .scaledBy(x: -1, y: 1)
            )
            : source
        let outputBufferPool = try outputBufferPool(for: outputExtent.size)
        guard let outputBufferLease = outputBufferPool.acquire() else {
            return nil
        }
        context.render(
            image,
            to: outputBufferLease.buffer,
            bounds: outputExtent,
            colorSpace: Self.colorSpace
        )
        var output: CGImage?
        let status = VTCreateCGImageFromCVPixelBuffer(
            outputBufferLease.buffer,
            options: nil,
            imageOut: &output
        )
        guard status == noErr, let output else {
            throw CameraCutoutCompositorError.cannotCreateImage
        }
        guard output.alphaInfo == .premultipliedFirst || output.alphaInfo == .premultipliedLast
        else {
            throw CameraCutoutCompositorError.invalidPremultipliedOutput
        }
        return CameraCutoutCompositedFrame(
            image: output,
            sourceTimestamp: sourceTimestamp,
            outputBufferLease: outputBufferLease
        )
    }

    private func outputBufferPool(for outputSize: CGSize) throws -> CameraCutoutOutputBufferPool {
        if let outputBufferPool, outputBufferPool.outputSize == outputSize {
            return outputBufferPool
        }
        let outputBufferPool = try CameraCutoutOutputBufferPool(outputSize: outputSize)
        self.outputBufferPool = outputBufferPool
        return outputBufferPool
    }

    private static func oneFrameDelayMatte(
        previous: CVPixelBuffer?,
        current: CVPixelBuffer,
        next: CVPixelBuffer
    ) -> CIImage {
        let currentImage = matteImage(current)
        guard let previous else {
            return currentImage
        }
        let previousImage = matteImage(previous)
        let nextImage = matteImage(next)
        let neighborDifference = difference(previousImage, nextImage)
        let currentDifference = minimum(
            difference(currentImage, previousImage),
            difference(currentImage, nextImage)
        )
        let neighborAgreement = smoothThreshold(
            neighborDifference,
            lower: 0.03,
            upper: 0.08
        ).applyingFilter("CIColorInvert")
        let currentDisagreement = smoothThreshold(
            currentDifference,
            lower: 0.08,
            upper: 0.18
        )
        let replacementMask = neighborAgreement.applyingFilter(
            "CIMultiplyBlendMode",
            parameters: [kCIInputBackgroundImageKey: currentDisagreement]
        )
        let average = scaled(previousImage, by: 0.5).applyingFilter(
            "CIAdditionCompositing",
            parameters: [kCIInputBackgroundImageKey: scaled(nextImage, by: 0.5)]
        )
        return average.applyingFilter(
            "CIBlendWithMask",
            parameters: [
                kCIInputBackgroundImageKey: currentImage,
                kCIInputMaskImageKey: replacementMask
            ]
        )
    }

    private static func isContinuous(
        _ current: PendingPortraitFrame,
        _ next: PendingPortraitFrame
    ) -> Bool {
        guard current.generation == next.generation,
              current.timestamp.isValid,
              next.timestamp.isValid
        else {
            return false
        }
        let gap = next.timestamp.seconds - current.timestamp.seconds
        return gap > 0 && gap <= maximumFrameGap
    }

    private static func squareImage(_ image: CIImage, outputExtent: CGRect) -> CIImage {
        let square = MODNetPortraitMattingProcessor.centerCroppedImage(image)
        let translated = square.transformed(
            by: CGAffineTransform(translationX: -square.extent.minX, y: -square.extent.minY)
        )
        let scaleX = outputExtent.width / square.extent.width
        let scaleY = outputExtent.height / square.extent.height
        return
            translated
            .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            .cropped(to: outputExtent)
    }

    private static func matteImage(_ buffer: CVPixelBuffer) -> CIImage {
        CIImage(
            cvPixelBuffer: buffer,
            options: [.colorSpace: linearGrayColorSpace]
        )
    }

    private static func difference(_ first: CIImage, _ second: CIImage) -> CIImage {
        first.applyingFilter(
            "CIDifferenceBlendMode",
            parameters: [kCIInputBackgroundImageKey: second]
        )
    }

    private static func minimum(_ first: CIImage, _ second: CIImage) -> CIImage {
        first.applyingFilter(
            "CIDarkenBlendMode",
            parameters: [kCIInputBackgroundImageKey: second]
        )
    }

    private static func scaled(_ image: CIImage, by scale: CGFloat) -> CIImage {
        colorMatrix(image, scale: scale)
    }

    private static func smoothThreshold(
        _ image: CIImage,
        lower: CGFloat,
        upper: CGFloat
    ) -> CIImage {
        let scale = 1 / (upper - lower)
        let normalized = colorMatrix(image, scale: scale, bias: -lower * scale).applyingFilter(
            "CIColorClamp",
            parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
            ]
        )
        let smoothstep = CIVector(x: 0, y: 0, z: 3, w: -2)
        return normalized.applyingFilter(
            "CIColorPolynomial",
            parameters: [
                "inputRedCoefficients": smoothstep,
                "inputGreenCoefficients": smoothstep,
                "inputBlueCoefficients": smoothstep,
                "inputAlphaCoefficients": CIVector(x: 0, y: 1, z: 0, w: 0)
            ]
        )
    }

    private static func colorMatrix(
        _ image: CIImage,
        scale: CGFloat,
        bias: CGFloat = 0
    ) -> CIImage {
        image.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: scale, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: scale, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: scale, w: 0),
                "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 0)
            ]
        )
    }

    private static let maximumFrameGap = 0.25
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let linearGrayColorSpace = CGColorSpace(name: CGColorSpace.linearGray)!
}

private final class CameraCutoutOutputBufferLease: @unchecked Sendable {
    let buffer: CVPixelBuffer
    private let releaseBuffer: @Sendable () -> Void

    init(buffer: CVPixelBuffer, releaseBuffer: @escaping @Sendable () -> Void) {
        self.buffer = buffer
        self.releaseBuffer = releaseBuffer
    }

    deinit {
        releaseBuffer()
    }
}

private final class CameraCutoutOutputBufferPool: @unchecked Sendable {
    struct Slot {
        let buffer: CVPixelBuffer
        var isAvailable = true
    }

    let outputSize: CGSize

    private let lock = NSLock()
    private let pool: CVPixelBufferPool
    private var slots: [Slot]
    private var nextSlotIndex = 0

    init(outputSize: CGSize) throws {
        self.outputSize = outputSize
        let width = Int(outputSize.width.rounded(.up))
        let height = Int(outputSize.height.rounded(.up))
        let poolAttributes: [CFString: Any] = [kCVPixelBufferPoolMinimumBufferCountKey: Self.bufferCount]
        let bufferAttributes: [CFString: Any] = [
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        var pool: CVPixelBufferPool?
        let poolStatus = CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            poolAttributes as CFDictionary,
            bufferAttributes as CFDictionary,
            &pool
        )
        guard poolStatus == kCVReturnSuccess, let pool else {
            throw CameraCutoutCompositorError.cannotCreateOutputBuffer
        }

        var slots: [Slot] = []
        for _ in 0..<Self.bufferCount {
            var buffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(
                kCFAllocatorDefault,
                pool,
                &buffer
            )
            guard status == kCVReturnSuccess, let buffer else {
                throw CameraCutoutCompositorError.cannotCreateOutputBuffer
            }
            CVBufferSetAttachment(
                buffer,
                kCVImageBufferAlphaChannelModeKey,
                kCVImageBufferAlphaChannelMode_PremultipliedAlpha,
                .shouldPropagate
            )
            CVBufferSetAttachment(
                buffer,
                kCVImageBufferAlphaChannelIsOpaque,
                kCFBooleanFalse,
                .shouldPropagate
            )
            slots.append(Slot(buffer: buffer))
        }
        self.pool = pool
        self.slots = slots
    }

    func acquire() -> CameraCutoutOutputBufferLease? {
        lock.withLock {
            for offset in 0..<slots.count {
                let index = (nextSlotIndex + offset) % slots.count
                guard slots[index].isAvailable else {
                    continue
                }
                slots[index].isAvailable = false
                nextSlotIndex = (index + 1) % slots.count
                return CameraCutoutOutputBufferLease(
                    buffer: slots[index].buffer,
                    releaseBuffer: { [weak self] in self?.release(index) }
                )
            }
            return nil
        }
    }

    private func release(_ index: Int) {
        lock.withLock {
            slots[index].isAvailable = true
        }
    }

    private static let bufferCount = 3
}
