import LuxelCore
import Testing

@Suite("Capture window snap frame resolver")
struct CaptureWindowSnapFrameResolverTests {
    @Test("resolves window frames into display-local coordinates")
    func resolvesWindowFramesIntoDisplayLocalCoordinates() throws {
        let display = try DisplayBounds(id: DisplayID(2), x: -1728, y: 120, width: 1728, height: 1117)
        let window = try windowTarget(
            id: 10,
            frame: CaptureRect(x: -1628, y: 220, width: 640, height: 360)
        )

        let frames = CaptureWindowSnapFrameResolver.windowFrames(on: display, from: [window])

        #expect(
            frames == [
                try CaptureRect(x: 100, y: 100, width: 640, height: 360)
            ])
    }

    @Test("ignores display targets windows without frames and windows outside display")
    func ignoresNonWindowTargetsAndOutOfDisplayWindows() throws {
        let display = try DisplayBounds(id: DisplayID(1), x: 0, y: 0, width: 1000, height: 800)
        let displayTarget = try CaptureTargetOption(
            id: "display-1",
            kind: .display,
            title: "Display",
            target: .display(display.id),
            pixelSize: PixelSize(width: display.width, height: display.height),
            frame: CaptureRect(x: 0, y: 0, width: 1000, height: 800)
        )
        let framelessWindow = try CaptureTargetOption(
            id: "window-1",
            kind: .window,
            title: "Frameless",
            target: .window(id: 1),
            pixelSize: PixelSize(width: 100, height: 100)
        )
        let otherDisplayWindow = try windowTarget(
            id: 2,
            frame: CaptureRect(x: 1200, y: 100, width: 100, height: 100)
        )

        let frames = CaptureWindowSnapFrameResolver.windowFrames(
            on: display,
            from: [displayTarget, framelessWindow, otherDisplayWindow]
        )

        #expect(frames.isEmpty)
    }

    private func windowTarget(id: UInt32, frame: CaptureRect) throws -> CaptureTargetOption {
        try CaptureTargetOption(
            id: "window-\(id)",
            kind: .window,
            title: "Window \(id)",
            target: .window(id: id),
            pixelSize: PixelSize(width: frame.width, height: frame.height),
            frame: frame
        )
    }
}
