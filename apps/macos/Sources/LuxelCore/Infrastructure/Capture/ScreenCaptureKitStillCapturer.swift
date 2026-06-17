import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

public final class ScreenCaptureKitStillCapturer: StillCapturer, @unchecked Sendable {
    private let contentFilterProvider: any ScreenCaptureKitContentFilterProvider
    private let configurationFactory: ScreenStillConfigurationFactory
    private let imageEncoder: ImageIOStillImageEncoder

    public init(
        contentFilterProvider: any ScreenCaptureKitContentFilterProvider = ShareableContentFilterProvider(),
        configurationFactory: ScreenStillConfigurationFactory = ScreenStillConfigurationFactory(),
        imageEncoder: ImageIOStillImageEncoder = ImageIOStillImageEncoder()
    ) {
        self.contentFilterProvider = contentFilterProvider
        self.configurationFactory = configurationFactory
        self.imageEncoder = imageEncoder
    }

    public func capture(_ request: ScreenshotRequest) async throws -> ImageData {
        let image = try await captureImage(request)
        let data = try imageEncoder.encode(image, format: request.format)

        return try ImageData(
            data: data,
            format: request.format,
            pixelSize: PixelSize(width: image.width, height: image.height)
        )
    }

    public func captureImage(_ request: ScreenshotRequest) async throws -> CGImage {
        let contentFilter = try await contentFilterProvider.contentFilter(for: request.target)
        let configuration = try configurationFactory.makeConfiguration(
            for: request,
            contentRect: contentFilter.contentRect,
            pointPixelScale: contentFilter.pointPixelScale
        )
        return try await SCScreenshotManager.captureImage(
            contentFilter: contentFilter,
            configuration: configuration
        )
    }
}

public struct ScreenStillConfigurationFactory: Sendable {
    private static let opaqueBackgroundColor = CGColor(gray: 0, alpha: 1)
    private static let transparentBackgroundColor = CGColor(gray: 0, alpha: 0)

    public init() {}

    public func makeConfiguration(
        for request: ScreenshotRequest,
        contentRect: CGRect,
        pointPixelScale: Float
    ) throws -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.showsCursor = request.includeCursor
        configuration.backgroundColor = request.backdrop.usesAlpha
            ? Self.transparentBackgroundColor
            : Self.opaqueBackgroundColor
        if request.backdrop.usesAlpha {
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
        }

        if case .area(_, let rect) = request.target {
            configuration.sourceRect = CGRect(
                x: rect.originX,
                y: rect.originY,
                width: rect.width,
                height: rect.height
            )
        }

        let pointSize = pointSize(for: request.target, contentRect: contentRect)
        let outputScale = request.scale == .native ? max(CGFloat(pointPixelScale), 1) : 1
        configuration.width = size_t(max(1, Int((pointSize.width * outputScale).rounded())))
        configuration.height = size_t(max(1, Int((pointSize.height * outputScale).rounded())))

        if request.target.isWindow {
            configuration.ignoreShadowsSingleWindow = request.backdrop == .transparent
        }

        return configuration
    }

    private func pointSize(for target: CaptureTarget, contentRect: CGRect) -> CGSize {
        if case .area(_, let rect) = target {
            return CGSize(width: rect.width, height: rect.height)
        }

        return contentRect.size
    }
}

public struct ImageIOStillImageEncoder: Sendable {
    public init() {}

    public func encode(_ image: CGImage, format: ScreenshotFormat) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            format.utType.identifier as CFString,
            1,
            nil
        ) else {
            throw ScreenCaptureKitStillCapturerError.encodingFailed(format)
        }

        CGImageDestinationAddImage(destination, image, format.imageDestinationOptions)

        guard CGImageDestinationFinalize(destination) else {
            throw ScreenCaptureKitStillCapturerError.encodingFailed(format)
        }

        return data as Data
    }
}

public enum ScreenCaptureKitStillCapturerError: Error, Equatable {
    case encodingFailed(ScreenshotFormat)
}

private extension CaptureTarget {
    var isWindow: Bool {
        if case .window = self {
            return true
        }

        return false
    }
}

private extension ScreenshotFormat {
    var utType: UTType {
        switch self {
        case .png:
            .png
        case .jpeg:
            .jpeg
        case .heic:
            .heic
        }
    }

    var imageDestinationOptions: CFDictionary? {
        switch self {
        case .jpeg:
            [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary
        case .png, .heic:
            nil
        }
    }
}
