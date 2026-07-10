import CoreImage
import CoreML
import CoreVideo
import Foundation
import OSLog

public enum MODNetPortraitMattingError: Error, Equatable {
    case missingModel
    case cannotCreateInputBuffer
    case cannotCreateOutputBuffer
    case missingInputFeature
    case missingOutputFeature
    case invalidOutputDimensions(width: Int, height: Int)
    case invalidOutputPixelFormat(OSType)
    case invalidOutputValue
}

public final class MODNetPortraitMattingProcessor: @unchecked Sendable {
    public static let inputSize = 512

    private let modelURL: URL?
    private let lock = NSLock()
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let configuration: MLModelConfiguration
    private var model: MLModel?
    private var inputBuffer: CVPixelBuffer?
    private var outputBufferPool: CVPixelBufferPool?
    private var outputBuffers: [CVPixelBuffer] = []
    private var nextOutputBufferIndex = 0
    private var predictionCount = 0

    public init(modelURL: URL?, computeUnits: MLComputeUnits = .all) {
        self.modelURL = modelURL
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        self.configuration = configuration
    }

    public var isPrepared: Bool {
        lock.withLock { model != nil }
    }

    public func prepare() throws {
        try lock.withLock {
            let loadStart = ContinuousClock.now
            let model = try loadedModel()
            let buffer = try reusableInputBuffer()
            context.render(
                CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5))
                    .cropped(to: Self.inputExtent),
                to: buffer,
                bounds: Self.inputExtent,
                colorSpace: Self.colorSpace
            )
            _ = try predict(model: model, inputBuffer: buffer)
            Self.logger.info(
                "MODNet prepared in \(loadStart.duration(to: .now).milliseconds, privacy: .public) ms"
            )
        }
    }

    public func alphaMatte(for cameraFrame: CVPixelBuffer) throws -> CVPixelBuffer {
        try lock.withLock {
            let model = try loadedModel()
            let buffer = try reusableInputBuffer()
            renderCenterCrop(cameraFrame, to: buffer)
            let matte = try predict(model: model, inputBuffer: buffer)
            return matte
        }
    }

    private func loadedModel() throws -> MLModel {
        if let model {
            return model
        }

        guard let modelURL, FileManager.default.fileExists(atPath: modelURL.path) else {
            throw MODNetPortraitMattingError.missingModel
        }

        let model = try MLModel(contentsOf: modelURL, configuration: configuration)
        guard model.modelDescription.inputDescriptionsByName[Self.inputName] != nil else {
            throw MODNetPortraitMattingError.missingInputFeature
        }
        guard model.modelDescription.outputDescriptionsByName[Self.outputName] != nil else {
            throw MODNetPortraitMattingError.missingOutputFeature
        }
        self.model = model
        return model
    }

    private func reusableInputBuffer() throws -> CVPixelBuffer {
        if let inputBuffer {
            return inputBuffer
        }

        var buffer: CVPixelBuffer?
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Self.inputSize,
            Self.inputSize,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let buffer else {
            throw MODNetPortraitMattingError.cannotCreateInputBuffer
        }
        inputBuffer = buffer
        return buffer
    }

    private func renderCenterCrop(_ cameraFrame: CVPixelBuffer, to destination: CVPixelBuffer) {
        let image = Self.centerCroppedImage(CIImage(cvPixelBuffer: cameraFrame))
        let scale = CGFloat(Self.inputSize) / image.extent.width
        let resized = image
            .transformed(by: CGAffineTransform(translationX: -image.extent.minX, y: -image.extent.minY))
            .transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        context.render(
            resized,
            to: destination,
            bounds: Self.inputExtent,
            colorSpace: Self.colorSpace
        )
    }

    private func predict(model: MLModel, inputBuffer: CVPixelBuffer) throws -> CVPixelBuffer {
        let input = try MLDictionaryFeatureProvider(dictionary: [
            Self.inputName: MLFeatureValue(pixelBuffer: inputBuffer)
        ])
        let outputBuffer = try reusableOutputBuffer()
        let options = MLPredictionOptions()
        options.outputBackings = [Self.outputName: outputBuffer]
        let features = try model.prediction(from: input, options: options)
        guard let matte = features.featureValue(for: Self.outputName)?.imageBufferValue else {
            throw MODNetPortraitMattingError.missingOutputFeature
        }
        let width = CVPixelBufferGetWidth(matte)
        let height = CVPixelBufferGetHeight(matte)
        guard width == Self.inputSize, height == Self.inputSize else {
            throw MODNetPortraitMattingError.invalidOutputDimensions(width: width, height: height)
        }
        let format = CVPixelBufferGetPixelFormatType(matte)
        guard format == kCVPixelFormatType_OneComponent16Half else {
            throw MODNetPortraitMattingError.invalidOutputPixelFormat(format)
        }
        predictionCount += 1
        if predictionCount == 1 || predictionCount.isMultiple(of: Self.alphaValidationInterval) {
            try Self.validateAlpha(matte)
        }
        return matte
    }

    private func reusableOutputBuffer() throws -> CVPixelBuffer {
        if outputBuffers.isEmpty {
            try makeOutputBufferPool()
        }
        guard !outputBuffers.isEmpty else {
            throw MODNetPortraitMattingError.cannotCreateOutputBuffer
        }
        let buffer = outputBuffers[nextOutputBufferIndex]
        nextOutputBufferIndex = (nextOutputBufferIndex + 1) % outputBuffers.count
        return buffer
    }

    private func makeOutputBufferPool() throws {
        let poolAttributes: [CFString: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey: Self.outputBufferCount
        ]
        let bufferAttributes: [CFString: Any] = [
            kCVPixelBufferWidthKey: Self.inputSize,
            kCVPixelBufferHeightKey: Self.inputSize,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_OneComponent16Half,
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
            throw MODNetPortraitMattingError.cannotCreateOutputBuffer
        }

        var buffers: [CVPixelBuffer] = []
        for _ in 0..<Self.outputBufferCount {
            var buffer: CVPixelBuffer?
            let status = CVPixelBufferPoolCreatePixelBuffer(
                kCFAllocatorDefault,
                pool,
                &buffer
            )
            guard status == kCVReturnSuccess, let buffer else {
                throw MODNetPortraitMattingError.cannotCreateOutputBuffer
            }
            buffers.append(buffer)
        }
        outputBufferPool = pool
        outputBuffers = buffers
    }

    private static func validateAlpha(_ matte: CVPixelBuffer) throws {
        CVPixelBufferLockBaseAddress(matte, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(matte, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(matte) else {
            throw MODNetPortraitMattingError.invalidOutputValue
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(matte)
        for rowIndex in stride(from: 0, to: inputSize, by: 8) {
            let row = baseAddress
                .advanced(by: rowIndex * bytesPerRow)
                .assumingMemoryBound(to: UInt16.self)
            for columnIndex in stride(from: 0, to: inputSize, by: 8) {
                let value = Float(Float16(bitPattern: row[columnIndex]))
                guard value.isFinite, (0...1).contains(value) else {
                    throw MODNetPortraitMattingError.invalidOutputValue
                }
            }
        }
    }

    public static func centerCroppedImage(_ image: CIImage) -> CIImage {
        let side = min(image.extent.width, image.extent.height)
        let cropRect = CGRect(
            x: image.extent.midX - side / 2,
            y: image.extent.midY - side / 2,
            width: side,
            height: side
        )
        return image.cropped(to: cropRect)
    }

    private static let inputName = "cameraImage"
    private static let outputName = "alphaMatte"
    private static let outputBufferCount = 3
    private static let alphaValidationInterval = 30
    private static let inputExtent = CGRect(x: 0, y: 0, width: inputSize, height: inputSize)
    private static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    private static let logger = Logger(subsystem: "media.luxel.app", category: "CameraCutout")
}

private extension Duration {
    var milliseconds: Double {
        let components = self.components
        return Double(components.seconds) * 1_000
            + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
