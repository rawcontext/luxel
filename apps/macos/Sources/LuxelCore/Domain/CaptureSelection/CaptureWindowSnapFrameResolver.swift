public enum CaptureWindowSnapFrameResolver {
    public static func windowFrames(
        on display: DisplayBounds,
        from targets: [CaptureTargetOption]
    ) -> [CaptureRect] {
        targets.compactMap { target in
            guard case .window = target.target,
                  let frame = target.frame
            else {
                return nil
            }

            return try? CaptureCoordinateMapper.localRect(fromGlobalRect: frame, in: display)
        }
    }
}
