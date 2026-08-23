import CoreGraphics
import CoreVideo
import Foundation

final class CameraCutoutOutputBufferLease: @unchecked Sendable {
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

final class CameraCutoutOutputBufferPool: @unchecked Sendable {
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
        let poolAttributes: [CFString: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey: Self.bufferCount
        ]
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
