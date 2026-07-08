import AppKit
import LuxelCore
import SwiftUI

extension View {
    func appKitCursor(_ cursor: NSCursor) -> some View {
        background(CursorRectView(cursor: cursor))
    }
}

enum CropperDragTarget: Equatable {
    case draw
    case move
    case resize(CaptureResizeHandle)
}

private struct CursorRectView: NSViewRepresentable {
    let cursor: NSCursor

    func makeNSView(context: Context) -> CursorRectNSView {
        let view = CursorRectNSView()
        view.cursor = cursor
        return view
    }

    func updateNSView(_ nsView: CursorRectNSView, context: Context) {
        nsView.cursor = cursor
    }
}

private final class CursorRectNSView: NSView {
    var cursor: NSCursor = .arrow {
        didSet {
            window?.invalidateCursorRects(for: self)
        }
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: cursor)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

extension CaptureResizeHandle {
    var resizeCursor: NSCursor {
        switch self {
        case .top, .bottom:
            .resizeUpDown
        case .left, .right:
            .resizeLeftRight
        case .topLeft, .bottomRight:
            CropperResizeCursors.topLeftBottomRight
        case .topRight, .bottomLeft:
            CropperResizeCursors.topRightBottomLeft
        }
    }
}

private enum CropperResizeCursors {
    static var topLeftBottomRight: NSCursor {
        diagonalResizeCursor(isRising: true)
    }

    static var topRightBottomLeft: NSCursor {
        diagonalResizeCursor(isRising: false)
    }

    private static func diagonalResizeCursor(isRising: Bool) -> NSCursor {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()

        let start = isRising ? NSPoint(x: 4, y: 4) : NSPoint(x: 4, y: 14)
        let end = isRising ? NSPoint(x: 14, y: 14) : NSPoint(x: 14, y: 4)
        let vector = CGVector(dx: end.x - start.x, dy: end.y - start.y)
        let length = max(1, hypot(vector.dx, vector.dy))
        let unit = CGVector(dx: vector.dx / length, dy: vector.dy / length)
        let normal = CGVector(dx: -unit.dy, dy: unit.dx)

        let segments = diagonalCursorSegments(start: start, end: end, unit: unit, normal: normal)
        drawCursorSegments(segments, color: .white, lineWidth: 4)
        drawCursorSegments(segments, color: .black, lineWidth: 2)

        image.unlockFocus()
        image.isTemplate = false
        return NSCursor(image: image, hotSpot: NSPoint(x: 9, y: 9))
    }

    private static func diagonalCursorSegments(
        start: NSPoint,
        end: NSPoint,
        unit: CGVector,
        normal: CGVector
    ) -> [(NSPoint, NSPoint)] {
        let arrowLength: CGFloat = 4
        let arrowSpread: CGFloat = 3

        return [
            (start, end),
            (
                start,
                NSPoint(
                    x: start.x + unit.dx * arrowLength + normal.dx * arrowSpread,
                    y: start.y + unit.dy * arrowLength + normal.dy * arrowSpread
                )
            ),
            (
                start,
                NSPoint(
                    x: start.x + unit.dx * arrowLength - normal.dx * arrowSpread,
                    y: start.y + unit.dy * arrowLength - normal.dy * arrowSpread
                )
            ),
            (
                end,
                NSPoint(
                    x: end.x - unit.dx * arrowLength + normal.dx * arrowSpread,
                    y: end.y - unit.dy * arrowLength + normal.dy * arrowSpread
                )
            ),
            (
                end,
                NSPoint(
                    x: end.x - unit.dx * arrowLength - normal.dx * arrowSpread,
                    y: end.y - unit.dy * arrowLength - normal.dy * arrowSpread
                )
            )
        ]
    }

    private static func drawCursorSegments(
        _ segments: [(NSPoint, NSPoint)],
        color: NSColor,
        lineWidth: CGFloat
    ) {
        color.setStroke()

        for (start, end) in segments {
            let path = NSBezierPath()
            path.lineWidth = lineWidth
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: start)
            path.line(to: end)
            path.stroke()
        }
    }
}
