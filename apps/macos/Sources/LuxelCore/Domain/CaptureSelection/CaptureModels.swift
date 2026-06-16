import Foundation

public struct CaptureRect: Codable, Equatable, Sendable {
    public let originX: Int
    public let originY: Int
    public let width: Int
    public let height: Int

    public init(x originX: Int, y originY: Int, width: Int, height: Int) throws {
        guard width > 0, height > 0 else {
            throw CaptureModelError.invalidDimensions
        }

        self.originX = originX
        self.originY = originY
        self.width = width
        self.height = height
    }

    private enum CodingKeys: String, CodingKey {
        case originX = "x"
        case originY = "y"
        case width
        case height
    }
}

public struct CapturePoint: Codable, Equatable, Sendable {
    public let xCoordinate: Int
    public let yCoordinate: Int

    public init(x xCoordinate: Int, y yCoordinate: Int) {
        self.xCoordinate = xCoordinate
        self.yCoordinate = yCoordinate
    }

    private enum CodingKeys: String, CodingKey {
        case xCoordinate = "x"
        case yCoordinate = "y"
    }
}

public struct CaptureAspectRatio: Codable, Equatable, Sendable {
    public static let widescreen16x9 = CaptureAspectRatio(uncheckedWidth: 16, height: 9)
    public static let standard4x3 = CaptureAspectRatio(uncheckedWidth: 4, height: 3)
    public static let square1x1 = CaptureAspectRatio(uncheckedWidth: 1, height: 1)
    public static let vertical9x16 = CaptureAspectRatio(uncheckedWidth: 9, height: 16)
    public static let ultrawide21x9 = CaptureAspectRatio(uncheckedWidth: 21, height: 9)

    public let width: Int
    public let height: Int

    public init(width: Int, height: Int) throws {
        guard width > 0, height > 0 else {
            throw CaptureModelError.invalidDimensions
        }

        self.width = width
        self.height = height
    }

    private init(uncheckedWidth width: Int, height: Int) {
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
    public let owningApplicationBundleIdentifier: String?
    public let owningApplicationProcessIdentifier: Int32?
    public let target: CaptureTarget
    public let pixelSize: PixelSize
    public let frame: CaptureRect?

    public init(
        id: String,
        kind: CaptureTargetKind,
        title: String,
        subtitle: String? = nil,
        owningApplicationBundleIdentifier: String? = nil,
        owningApplicationProcessIdentifier: Int32? = nil,
        target: CaptureTarget,
        pixelSize: PixelSize,
        frame: CaptureRect? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.subtitle = subtitle
        self.owningApplicationBundleIdentifier = owningApplicationBundleIdentifier
        self.owningApplicationProcessIdentifier = owningApplicationProcessIdentifier
        self.target = target
        self.pixelSize = pixelSize
        self.frame = frame
    }
}

public enum CaptureModelError: Error, Equatable {
    case invalidDimensions
    case selectionOutsideDisplay
}
