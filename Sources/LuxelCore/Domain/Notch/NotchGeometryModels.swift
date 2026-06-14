import Foundation

public struct NotchScreenRect: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) throws {
        guard x.isFinite, y.isFinite, width.isFinite, height.isFinite, width > 0, height > 0 else {
            throw NotchGeometryError.invalidRect
        }

        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var minX: Double { x }
    public var maxX: Double { x + width }
    public var minY: Double { y }
    public var maxY: Double { y + height }

    public func contains(_ rect: NotchScreenRect) -> Bool {
        rect.minX >= minX &&
            rect.maxX <= maxX &&
            rect.minY >= minY &&
            rect.maxY <= maxY
    }
}

public struct NotchSafeAreaInsets: Codable, Equatable, Sendable {
    public let top: Double
    public let left: Double
    public let bottom: Double
    public let right: Double

    public init(top: Double, left: Double = 0, bottom: Double = 0, right: Double = 0) throws {
        guard [top, left, bottom, right].allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            throw NotchGeometryError.invalidInsets
        }

        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }
}

public struct NotchDisplayDescriptor: Codable, Equatable, Sendable {
    public let displayID: DisplayID
    public let frame: NotchScreenRect
    public let safeAreaInsets: NotchSafeAreaInsets
    public let auxiliaryTopLeftArea: NotchScreenRect?
    public let auxiliaryTopRightArea: NotchScreenRect?
    public let isBuiltIn: Bool
    public let isVisible: Bool

    public init(
        displayID: DisplayID,
        frame: NotchScreenRect,
        safeAreaInsets: NotchSafeAreaInsets,
        auxiliaryTopLeftArea: NotchScreenRect? = nil,
        auxiliaryTopRightArea: NotchScreenRect? = nil,
        isBuiltIn: Bool,
        isVisible: Bool = true
    ) {
        self.displayID = displayID
        self.frame = frame
        self.safeAreaInsets = safeAreaInsets
        self.auxiliaryTopLeftArea = auxiliaryTopLeftArea
        self.auxiliaryTopRightArea = auxiliaryTopRightArea
        self.isBuiltIn = isBuiltIn
        self.isVisible = isVisible
    }
}

public struct NotchGeometry: Codable, Equatable, Sendable {
    public let displayID: DisplayID
    public let screenFrame: NotchScreenRect
    public let safeAreaTopInset: Double
    public let auxiliaryTopLeftArea: NotchScreenRect
    public let auxiliaryTopRightArea: NotchScreenRect
    public let cameraHousingRect: NotchScreenRect

    public static func resolve(from display: NotchDisplayDescriptor) -> NotchGeometry? {
        guard display.isVisible,
              display.isBuiltIn,
              display.safeAreaInsets.top > 0,
              let leftArea = display.auxiliaryTopLeftArea,
              let rightArea = display.auxiliaryTopRightArea,
              leftArea.maxX < rightArea.minX else {
            return nil
        }

        let housingY = min(leftArea.minY, rightArea.minY)
        let housingMaxY = max(leftArea.maxY, rightArea.maxY)

        guard let housingRect = try? NotchScreenRect(
            x: leftArea.maxX,
            y: housingY,
            width: rightArea.minX - leftArea.maxX,
            height: housingMaxY - housingY
        ), display.frame.contains(housingRect) else {
            return nil
        }

        return NotchGeometry(
            displayID: display.displayID,
            screenFrame: display.frame,
            safeAreaTopInset: display.safeAreaInsets.top,
            auxiliaryTopLeftArea: leftArea,
            auxiliaryTopRightArea: rightArea,
            cameraHousingRect: housingRect
        )
    }
}

public struct NotchSurfacePreferences: Codable, Equatable, Sendable {
    public static let defaults = NotchSurfacePreferences()

    public let isEnabled: Bool
    public let fallbackToFloatingHUDWhenUnavailable: Bool

    public init(
        isEnabled: Bool = true,
        fallbackToFloatingHUDWhenUnavailable: Bool = true
    ) {
        self.isEnabled = isEnabled
        self.fallbackToFloatingHUDWhenUnavailable = fallbackToFloatingHUDWhenUnavailable
    }
}

public enum RecordingSurfaceSelection: Equatable, Sendable {
    case notch(NotchGeometry)
    case floatingHUD(RecordingSurfaceFallbackReason)
    case menuBarOnly(RecordingSurfaceFallbackReason)
}

public enum RecordingSurfaceFallbackReason: String, Codable, Equatable, Sendable {
    case notchDisabled
    case noNotchedDisplay
}

public enum RecordingSurfaceSelector {
    public static func select(
        from displays: [NotchDisplayDescriptor],
        preferences: NotchSurfacePreferences = .defaults
    ) -> RecordingSurfaceSelection {
        guard preferences.isEnabled else {
            return fallbackSelection(
                reason: .notchDisabled,
                preferences: preferences
            )
        }

        if let geometry = displays.lazy.compactMap(NotchGeometry.resolve(from:)).first {
            return .notch(geometry)
        }

        return fallbackSelection(
            reason: .noNotchedDisplay,
            preferences: preferences
        )
    }

    private static func fallbackSelection(
        reason: RecordingSurfaceFallbackReason,
        preferences: NotchSurfacePreferences
    ) -> RecordingSurfaceSelection {
        if preferences.fallbackToFloatingHUDWhenUnavailable {
            .floatingHUD(reason)
        } else {
            .menuBarOnly(reason)
        }
    }
}

public enum NotchGeometryError: Error, Equatable {
    case invalidRect
    case invalidInsets
}
