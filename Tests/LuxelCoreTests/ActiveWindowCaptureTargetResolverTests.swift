import LuxelCore
import Testing

@Suite("Active window capture target resolver")
struct ActiveWindowCaptureTargetResolverTests {
    @Test("resolves first matching window target from ordered window IDs")
    func resolvesFirstMatchingWindowTarget() throws {
        let first = try windowTarget(id: 10, title: "First")
        let second = try windowTarget(id: 20, title: "Second")
        let display = try displayTarget()

        let resolved = ActiveWindowCaptureTargetResolver().resolve(
            from: [display, first, second],
            orderedWindowIDs: [99, 20, 10]
        )

        #expect(resolved == second)
    }

    @Test("ignores display targets and returns nil without a window match")
    func ignoresDisplayTargetsAndReturnsNilWithoutWindowMatch() throws {
        let resolved = ActiveWindowCaptureTargetResolver().resolve(
            from: [try displayTarget()],
            orderedWindowIDs: [42]
        )

        #expect(resolved == nil)
    }

    private func windowTarget(id: UInt32, title: String) throws -> CaptureTargetOption {
        CaptureTargetOption(
            id: "window-\(id)",
            kind: .window,
            title: title,
            target: .window(id: id),
            pixelSize: try PixelSize(width: 640, height: 480),
            frame: try CaptureRect(x: 0, y: 0, width: 640, height: 480)
        )
    }

    private func displayTarget() throws -> CaptureTargetOption {
        CaptureTargetOption(
            id: "display-1",
            kind: .display,
            title: "Display",
            target: .display(DisplayID(1)),
            pixelSize: try PixelSize(width: 1280, height: 720),
            frame: try CaptureRect(x: 0, y: 0, width: 1280, height: 720)
        )
    }
}
