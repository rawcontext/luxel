public enum CursorCoordinateMapper {
    public static func localPoint(
        fromGlobalPoint point: CursorPoint,
        in captureFrame: CaptureRect
    ) throws -> CursorPoint {
        try CursorPoint(
            x: point.x - Double(captureFrame.x),
            y: point.y - Double(captureFrame.y)
        )
    }
}
