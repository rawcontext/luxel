import Foundation

private struct DecodedCameraOverlayShape {
    let shape: CameraOverlayShape
    let legacyBackgroundEffect: CameraBackgroundEffect
}

private func decodeCameraOverlayShape<Key: CodingKey>(
    from container: KeyedDecodingContainer<Key>,
    forKey key: Key
) throws -> DecodedCameraOverlayShape {
    let rawValue =
        try container.decodeIfPresent(String.self, forKey: key)
        ?? CameraOverlayShape.circle.rawValue
    let isLegacyCutout = rawValue == "cutout"
    guard let shape = CameraOverlayShape(rawValue: rawValue) ?? (isLegacyCutout ? .circle : nil)
    else {
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "Unknown camera overlay shape: \(rawValue)"
        )
    }
    return DecodedCameraOverlayShape(
        shape: shape,
        legacyBackgroundEffect: isLegacyCutout ? .portraitCutout : .none
    )
}

private func decodeCameraBackgroundEffect<Key: CodingKey>(
    from container: KeyedDecodingContainer<Key>,
    forKey key: Key,
    legacyDefault: CameraBackgroundEffect
) throws -> CameraBackgroundEffect {
    try container.decodeIfPresent(CameraBackgroundEffect.self, forKey: key) ?? legacyDefault
}

public enum CameraDeviceKind: String, Codable, Equatable, Sendable {
    case builtIn
    case external
    case continuity
    case deskView
    case unknown
}

public struct CameraDeviceOption: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let kind: CameraDeviceKind

    public init(id: String, name: String, kind: CameraDeviceKind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

public struct CameraRecordingOptions: Codable, Equatable, Sendable {
    public let deviceID: String?
    public let isEnabled: Bool
    public let recordsSeparateTrack: Bool
    public let previewStyle: CameraPreviewStyle

    public init(
        deviceID: String? = nil,
        isEnabled: Bool = false,
        recordsSeparateTrack: Bool = true,
        previewStyle: CameraPreviewStyle = CameraPreviewStyle()
    ) {
        self.deviceID = deviceID.flatMap(Self.nonEmpty)
        self.isEnabled = isEnabled
        self.recordsSeparateTrack = recordsSeparateTrack
        self.previewStyle = previewStyle
    }

    private static func nonEmpty(_ value: String) -> String? {
        value.isEmpty ? nil : value
    }

    public func replacingPreviewStyle(_ previewStyle: CameraPreviewStyle) -> CameraRecordingOptions {
        CameraRecordingOptions(
            deviceID: deviceID,
            isEnabled: isEnabled,
            recordsSeparateTrack: recordsSeparateTrack,
            previewStyle: previewStyle
        )
    }
}

public struct CameraPreviewStyle: Codable, Equatable, Sendable {
    public let shape: CameraOverlayShape
    public let size: CameraPreviewSize
    public let isMirrored: Bool
    public let backgroundEffect: CameraBackgroundEffect

    public init(
        shape: CameraOverlayShape = .circle,
        size: CameraPreviewSize = .medium,
        isMirrored: Bool = true,
        backgroundEffect: CameraBackgroundEffect = .none
    ) {
        self.shape = shape
        self.size = size
        self.isMirrored = isMirrored
        self.backgroundEffect = backgroundEffect
    }

    private enum CodingKeys: String, CodingKey {
        case shape
        case size
        case isMirrored
        case backgroundEffect
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedShape = try decodeCameraOverlayShape(from: container, forKey: .shape)
        self.init(
            shape: decodedShape.shape,
            size: try container.decodeIfPresent(CameraPreviewSize.self, forKey: .size) ?? .medium,
            isMirrored: try container.decodeIfPresent(Bool.self, forKey: .isMirrored) ?? true,
            backgroundEffect: try decodeCameraBackgroundEffect(
                from: container,
                forKey: .backgroundEffect,
                legacyDefault: decodedShape.legacyBackgroundEffect
            )
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(shape, forKey: .shape)
        try container.encode(size, forKey: .size)
        try container.encode(isMirrored, forKey: .isMirrored)
        try container.encode(backgroundEffect, forKey: .backgroundEffect)
    }
}

public enum CameraBackgroundEffect: String, Codable, CaseIterable, Equatable, Sendable {
    case none
    case portraitCutout
    case greenScreen

    public var usesPortraitMatting: Bool {
        self == .portraitCutout
    }

    public var removesBackground: Bool {
        self != .none
    }
}

public enum CameraPreviewSize: String, Codable, CaseIterable, Equatable, Sendable {
    case small
    case medium
    case large
}

public struct CameraOverlayPlan: Codable, Equatable, Sendable {
    public let placement: CameraOverlayPlacement
    public let widthFraction: Double
    public let shape: CameraOverlayShape
    public let showsBorder: Bool
    public let backgroundEffect: CameraBackgroundEffect

    public init(
        placement: CameraOverlayPlacement = .anchor(.bottomRight),
        widthFraction: Double = 0.25,
        shape: CameraOverlayShape = .circle,
        showsBorder: Bool = true,
        backgroundEffect: CameraBackgroundEffect = .none
    ) throws {
        guard widthFraction.isFinite, (0.15...0.4).contains(widthFraction) else {
            throw WebcamOverlayModelError.invalidWidthFraction
        }

        self.placement = placement
        self.widthFraction = widthFraction
        self.shape = shape
        self.showsBorder = showsBorder
        self.backgroundEffect = backgroundEffect
    }

    private enum CodingKeys: String, CodingKey {
        case placement
        case widthFraction
        case shape
        case showsBorder
        case backgroundEffect
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedShape = try decodeCameraOverlayShape(from: container, forKey: .shape)
        try self.init(
            placement: container.decode(CameraOverlayPlacement.self, forKey: .placement),
            widthFraction: container.decode(Double.self, forKey: .widthFraction),
            shape: decodedShape.shape,
            showsBorder: container.decodeIfPresent(Bool.self, forKey: .showsBorder) ?? true,
            backgroundEffect: decodeCameraBackgroundEffect(
                from: container,
                forKey: .backgroundEffect,
                legacyDefault: decodedShape.legacyBackgroundEffect
            )
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(placement, forKey: .placement)
        try container.encode(widthFraction, forKey: .widthFraction)
        try container.encode(shape, forKey: .shape)
        try container.encode(showsBorder, forKey: .showsBorder)
        try container.encode(backgroundEffect, forKey: .backgroundEffect)
    }

    public func rect(in outputSize: PixelSize) throws -> CaptureRect {
        let overlayWidth = max(1, Int((Double(outputSize.width) * widthFraction).rounded()))
        let overlayHeight = overlayWidth

        guard overlayWidth <= outputSize.width, overlayHeight <= outputSize.height else {
            throw WebcamOverlayModelError.overlayOutsideFrame
        }

        switch placement {
        case .anchor(let anchor):
            return try anchor.rect(
                overlayWidth: overlayWidth,
                overlayHeight: overlayHeight,
                outputSize: outputSize
            )
        case .normalizedPoint(let point):
            let centerX = point.xCoordinate * Double(outputSize.width)
            let centerY = point.yCoordinate * Double(outputSize.height)
            let originX = Int((centerX - Double(overlayWidth) / 2).rounded())
            let originY = Int((centerY - Double(overlayHeight) / 2).rounded())
            guard originX >= 0,
                originY >= 0,
                originX + overlayWidth <= outputSize.width,
                originY + overlayHeight <= outputSize.height
            else {
                throw WebcamOverlayModelError.overlayOutsideFrame
            }

            return try CaptureRect(
                x: originX,
                y: originY,
                width: overlayWidth,
                height: overlayHeight
            )
        }
    }
}

public enum CameraOverlayPlacement: Codable, Equatable, Sendable {
    case anchor(CameraOverlayAnchor)
    case normalizedPoint(NormalizedPoint)
}

public enum CameraOverlayAnchor: String, Codable, CaseIterable, Equatable, Sendable {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    fileprivate func rect(
        overlayWidth: Int,
        overlayHeight: Int,
        outputSize: PixelSize
    ) throws -> CaptureRect {
        let margin = max(16, Int((Double(outputSize.width) * 0.03).rounded()))
        let originX =
            switch self {
            case .topLeft, .bottomLeft:
                margin
            case .topRight, .bottomRight:
                outputSize.width - overlayWidth - margin
            }
        let originY =
            switch self {
            case .topLeft, .topRight:
                margin
            case .bottomLeft, .bottomRight:
                outputSize.height - overlayHeight - margin
            }

        guard originX >= 0, originY >= 0 else {
            throw WebcamOverlayModelError.overlayOutsideFrame
        }

        return try CaptureRect(x: originX, y: originY, width: overlayWidth, height: overlayHeight)
    }
}

public enum CameraOverlayShape: String, Codable, CaseIterable, Equatable, Sendable {
    case circle
    case roundedRect
    case square
}

public struct NormalizedPoint: Codable, Equatable, Sendable {
    public let xCoordinate: Double
    public let yCoordinate: Double

    public init(x xCoordinate: Double, y yCoordinate: Double) throws {
        guard xCoordinate.isFinite,
            yCoordinate.isFinite,
            (0...1).contains(xCoordinate),
            (0...1).contains(yCoordinate)
        else {
            throw WebcamOverlayModelError.invalidNormalizedPoint
        }

        self.xCoordinate = xCoordinate
        self.yCoordinate = yCoordinate
    }

    private enum CodingKeys: String, CodingKey {
        case xCoordinate = "x"
        case yCoordinate = "y"
    }
}

public enum WebcamOverlayModelError: Error, Equatable {
    case invalidWidthFraction
    case invalidNormalizedPoint
    case overlayOutsideFrame
}
