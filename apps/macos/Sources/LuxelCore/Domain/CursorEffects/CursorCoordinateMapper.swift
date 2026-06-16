public enum CursorCoordinateMapper {
    public static func localPoint(
        fromGlobalPoint point: CursorPoint,
        in captureFrame: CaptureRect
    ) throws -> CursorPoint {
        try CursorPoint(
            x: point.xCoordinate - Double(captureFrame.originX),
            y: point.yCoordinate - Double(captureFrame.originY)
        )
    }
}
