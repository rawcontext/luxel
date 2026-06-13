public struct DisplayBounds: Codable, Equatable, Sendable {
    public let id: DisplayID
    public let x: Int
    public let y: Int
    public let width: Int
    public let height: Int

    public init(id: DisplayID, x: Int, y: Int, width: Int, height: Int) throws {
        guard width > 0, height > 0 else {
            throw CaptureModelError.invalidDimensions
        }

        self.id = id
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public enum CaptureCoordinateMapper {
    public static func recordingRect(
        fromTopLeftSelection selection: CaptureRect,
        in display: DisplayBounds
    ) throws -> CaptureRect {
        guard selection.x >= 0,
              selection.y >= 0,
              selection.x + selection.width <= display.width,
              selection.y + selection.height <= display.height else {
            throw CaptureModelError.selectionOutsideDisplay
        }

        return try CaptureRect(
            x: selection.x,
            y: display.height - (selection.y + selection.height),
            width: selection.width,
            height: selection.height
        )
    }

    public static func localRect(
        fromGlobalRect rect: CaptureRect,
        in display: DisplayBounds
    ) throws -> CaptureRect {
        let localRect = try CaptureRect(
            x: rect.x - display.x,
            y: rect.y - display.y,
            width: rect.width,
            height: rect.height
        )

        guard localRect.x >= 0,
              localRect.y >= 0,
              localRect.x + localRect.width <= display.width,
              localRect.y + localRect.height <= display.height else {
            throw CaptureModelError.selectionOutsideDisplay
        }

        return localRect
    }
}
