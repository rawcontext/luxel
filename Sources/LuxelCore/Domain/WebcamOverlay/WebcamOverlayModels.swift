import Foundation

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
}

public struct CameraPreviewStyle: Codable, Equatable, Sendable {
    public let shape: CameraOverlayShape
    public let size: CameraPreviewSize
    public let isMirrored: Bool

    public init(
        shape: CameraOverlayShape = .circle,
        size: CameraPreviewSize = .medium,
        isMirrored: Bool = true
    ) {
        self.shape = shape
        self.size = size
        self.isMirrored = isMirrored
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

    public init(
        placement: CameraOverlayPlacement = .anchor(.bottomRight),
        widthFraction: Double = 0.25,
        shape: CameraOverlayShape = .circle,
        showsBorder: Bool = true
    ) throws {
        guard widthFraction.isFinite, (0.15...0.4).contains(widthFraction) else {
            throw WebcamOverlayModelError.invalidWidthFraction
        }

        self.placement = placement
        self.widthFraction = widthFraction
        self.shape = shape
        self.showsBorder = showsBorder
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
            let centerX = point.x * Double(outputSize.width)
            let centerY = point.y * Double(outputSize.height)
            let originX = Int((centerX - Double(overlayWidth) / 2).rounded())
            let originY = Int((centerY - Double(overlayHeight) / 2).rounded())
            guard originX >= 0,
                  originY >= 0,
                  originX + overlayWidth <= outputSize.width,
                  originY + overlayHeight <= outputSize.height else {
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
        let x = switch self {
        case .topLeft, .bottomLeft:
            margin
        case .topRight, .bottomRight:
            outputSize.width - overlayWidth - margin
        }
        let y = switch self {
        case .topLeft, .topRight:
            margin
        case .bottomLeft, .bottomRight:
            outputSize.height - overlayHeight - margin
        }

        guard x >= 0, y >= 0 else {
            throw WebcamOverlayModelError.overlayOutsideFrame
        }

        return try CaptureRect(x: x, y: y, width: overlayWidth, height: overlayHeight)
    }
}

public enum CameraOverlayShape: String, Codable, CaseIterable, Equatable, Sendable {
    case circle
    case roundedRect
}

public struct NormalizedPoint: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) throws {
        guard x.isFinite,
              y.isFinite,
              (0...1).contains(x),
              (0...1).contains(y) else {
            throw WebcamOverlayModelError.invalidNormalizedPoint
        }

        self.x = x
        self.y = y
    }
}

public enum WebcamOverlayModelError: Error, Equatable {
    case invalidWidthFraction
    case invalidNormalizedPoint
    case overlayOutsideFrame
}
