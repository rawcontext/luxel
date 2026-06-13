import Foundation

public struct CaptureRect: Codable, Equatable, Sendable {
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    public init(x: Int, y: Int, width: Int, height: Int) throws {
        guard width > 0, height > 0 else {
            throw CaptureModelError.invalidDimensions
        }

        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct CapturePoint: Codable, Equatable, Sendable {
    public let x: Int
    public let y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

public struct CaptureAspectRatio: Codable, Equatable, Sendable {
    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) throws {
        guard width > 0, height > 0 else {
            throw CaptureModelError.invalidDimensions
        }

        self.width = width
        self.height = height
    }

    public var value: Double {
        Double(width) / Double(height)
    }
}

public struct DisplayID: Codable, Equatable, Hashable, Sendable {
    public let rawValue: UInt32

    public init(_ rawValue: UInt32) {
        self.rawValue = rawValue
    }
}

public enum CaptureTarget: Codable, Equatable, Sendable {
    case display(DisplayID)
    case window(id: UInt32)
    case area(displayID: DisplayID, rect: CaptureRect)
}

public enum CaptureTargetKind: String, Codable, CaseIterable, Equatable, Sendable {
    case display
    case window
}

public struct CaptureTargetOption: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: CaptureTargetKind
    public let title: String
    public let subtitle: String?
    public let target: CaptureTarget
    public let pixelSize: PixelSize
    public let frame: CaptureRect?

    public init(
        id: String,
        kind: CaptureTargetKind,
        title: String,
        subtitle: String? = nil,
        target: CaptureTarget,
        pixelSize: PixelSize,
        frame: CaptureRect? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.target = target
        self.pixelSize = pixelSize
        self.frame = frame
    }
}

public enum CaptureModelError: Error, Equatable {
    case invalidDimensions
    case selectionOutsideDisplay
}
