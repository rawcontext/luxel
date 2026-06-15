public struct DisplayBounds: Codable, Equatable, Sendable {
    public let id: DisplayID
    public let originX: Int
    public let originY: Int
    public let width: Int
    public let height: Int

    public init(id: DisplayID, x originX: Int, y originY: Int, width: Int, height: Int) throws {
        guard width > 0, height > 0 else {
            throw CaptureModelError.invalidDimensions
        }

        self.id = id
        self.originX = originX
        self.originY = originY
        self.width = width
        self.height = height
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case originX = "x"
        case originY = "y"
        case width
        case height
    }
}

public enum CaptureCoordinateMapper {
    public static func recordingRect(
        fromTopLeftSelection selection: CaptureRect,
        in display: DisplayBounds
    ) throws -> CaptureRect {
        guard selection.originX >= 0,
              selection.originY >= 0,
              selection.originX + selection.width <= display.width,
              selection.originY + selection.height <= display.height else {
            throw CaptureModelError.selectionOutsideDisplay
        }

        return try CaptureRect(
            x: selection.originX,
            y: display.height - (selection.originY + selection.height),
            width: selection.width,
            height: selection.height
        )
    }

    public static func topLeftSelection(
        fromRecordingRect rect: CaptureRect,
        in display: DisplayBounds
    ) throws -> CaptureRect {
        guard rect.originX >= 0,
              rect.originY >= 0,
              rect.originX + rect.width <= display.width,
              rect.originY + rect.height <= display.height else {
            throw CaptureModelError.selectionOutsideDisplay
        }

        return try CaptureRect(
            x: rect.originX,
            y: display.height - (rect.originY + rect.height),
            width: rect.width,
            height: rect.height
        )
    }

    public static func localRect(
        fromGlobalRect rect: CaptureRect,
        in display: DisplayBounds
    ) throws -> CaptureRect {
        let localRect = try CaptureRect(
            x: rect.originX - display.originX,
            y: rect.originY - display.originY,
            width: rect.width,
            height: rect.height
        )

        guard localRect.originX >= 0,
              localRect.originY >= 0,
              localRect.originX + localRect.width <= display.width,
              localRect.originY + localRect.height <= display.height else {
            throw CaptureModelError.selectionOutsideDisplay
        }

        return localRect
    }
}
