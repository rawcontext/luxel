import LuxelCore
import Testing

@Suite("Fullscreen capture target resolver")
struct FullscreenCaptureTargetResolverTests {
    @Test("prefers display under pointer over selected display")
    func prefersPointerDisplayOverSelectedDisplay() throws {
        let first = try displayTarget(id: 1)
        let second = try displayTarget(id: 2)

        let resolved = FullscreenCaptureTargetResolver().resolve(
            from: [first, second],
            pointerDisplayID: DisplayID(2),
            selectedTargetID: first.id
        )

        #expect(resolved == second)
    }

    @Test("falls back to selected display when pointer display is unavailable")
    func fallsBackToSelectedDisplayWhenPointerDisplayIsUnavailable() throws {
        let first = try displayTarget(id: 1)
        let second = try displayTarget(id: 2)

        let resolved = FullscreenCaptureTargetResolver().resolve(
            from: [first, second],
            pointerDisplayID: DisplayID(99),
            selectedTargetID: second.id
        )

        #expect(resolved == second)
    }

    @Test("ignores selected window and falls back to first display")
    func ignoresSelectedWindowAndFallsBackToFirstDisplay() throws {
        let window = try windowTarget(id: 10)
        let display = try displayTarget(id: 1)

        let resolved = FullscreenCaptureTargetResolver().resolve(
            from: [window, display],
            pointerDisplayID: nil,
            selectedTargetID: window.id
        )

        #expect(resolved == display)
    }

    @Test("returns nil without display targets")
    func returnsNilWithoutDisplayTargets() throws {
        let resolved = FullscreenCaptureTargetResolver().resolve(
            from: [try windowTarget(id: 10)],
            pointerDisplayID: DisplayID(1),
            selectedTargetID: nil
        )

        #expect(resolved == nil)
    }

    private func displayTarget(id: UInt32) throws -> CaptureTargetOption {
        CaptureTargetOption(
            id: "display-\(id)",
            kind: .display,
            title: "Display \(id)",
            target: .display(DisplayID(id)),
            pixelSize: try PixelSize(width: 1280, height: 720),
            frame: try CaptureRect(x: 0, y: 0, width: 1280, height: 720)
        )
    }

    private func windowTarget(id: UInt32) throws -> CaptureTargetOption {
        CaptureTargetOption(
            id: "window-\(id)",
            kind: .window,
            title: "Window \(id)",
            target: .window(id: id),
            pixelSize: try PixelSize(width: 640, height: 480),
            frame: try CaptureRect(x: 0, y: 0, width: 640, height: 480)
        )
    }
}
