import AppKit
import SwiftUI

final class LuxelMenuPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

struct LuxelMenuPanelChrome<Content: View>: View {
    let arrowCenterX: CGFloat
    let arrowHeight: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        let shape = LuxelMenuPanelShape(arrowCenterX: arrowCenterX, arrowHeight: arrowHeight)

        content
            .padding(.top, arrowHeight)
            .glassEffect(.regular, in: shape)
            .overlay {
                shape
                    .stroke(.white.opacity(0.34), lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .background(Color.clear)
    }
}

private struct LuxelMenuPanelShape: Shape {
    let arrowCenterX: CGFloat
    let arrowHeight: CGFloat
    private let arrowWidth: CGFloat = 24
    private let panelCornerRadius: CGFloat = 22

    func path(in rect: CGRect) -> Path {
        let bodyMinY = rect.minY + arrowHeight
        let bodyHeight = rect.maxY - bodyMinY
        let radius = min(panelCornerRadius, rect.width / 2, bodyHeight / 2)
        let arrowHalfWidth = arrowWidth / 2
        let centerX = min(
            max(arrowCenterX, rect.minX + radius + arrowHalfWidth),
            rect.maxX - radius - arrowHalfWidth
        )
        let arrowLeft = centerX - arrowHalfWidth
        let arrowRight = centerX + arrowHalfWidth
        var path = Path()

        path.move(to: CGPoint(x: rect.minX + radius, y: bodyMinY))
        path.addLine(to: CGPoint(x: arrowLeft, y: bodyMinY))
        path.addLine(to: CGPoint(x: centerX, y: rect.minY))
        path.addLine(to: CGPoint(x: arrowRight, y: bodyMinY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: bodyMinY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: bodyMinY + radius),
            control: CGPoint(x: rect.maxX, y: bodyMinY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - radius),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX, y: bodyMinY + radius))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + radius, y: bodyMinY),
            control: CGPoint(x: rect.minX, y: bodyMinY)
        )
        path.closeSubpath()

        return path
    }
}

final class LuxelMenuPanelContentView: NSView {
    private let arrowHeight: CGFloat
    private let maskLayer = CAShapeLayer()

    var arrowCenterX: CGFloat = 0 {
        didSet {
            needsLayout = true
        }
    }

    init(frame frameRect: NSRect, arrowHeight: CGFloat) {
        self.arrowHeight = arrowHeight
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.mask = maskLayer
        maskLayer.fillColor = NSColor.black.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()

        maskLayer.frame = bounds
        maskLayer.path = LuxelMenuPanelPath.bezierPath(
            in: bounds,
            arrowCenterX: arrowCenterX,
            arrowHeight: arrowHeight
        ).cgPath
    }
}

private enum LuxelMenuPanelPath {
    static let cornerRadius: CGFloat = 22
    private static let arrowWidth: CGFloat = 24

    static func bezierPath(
        in bounds: CGRect,
        arrowCenterX: CGFloat,
        arrowHeight: CGFloat
    ) -> NSBezierPath {
        guard arrowHeight > 0 else {
            return NSBezierPath(
                roundedRect: bounds,
                xRadius: cornerRadius,
                yRadius: cornerRadius
            )
        }

        let bodyMaxY = bounds.maxY - arrowHeight
        let radius = min(cornerRadius, bounds.width / 2, bodyMaxY / 2)
        let arrowHalfWidth = arrowWidth / 2
        let centerX = min(
            max(arrowCenterX, bounds.minX + radius + arrowHalfWidth),
            bounds.maxX - radius - arrowHalfWidth
        )
        let arrowLeft = centerX - arrowHalfWidth
        let arrowRight = centerX + arrowHalfWidth
        let path = NSBezierPath()

        path.move(to: CGPoint(x: bounds.minX + radius, y: bounds.minY))
        path.line(to: CGPoint(x: bounds.maxX - radius, y: bounds.minY))
        path.curve(
            to: CGPoint(x: bounds.maxX, y: bounds.minY + radius),
            controlPoint1: CGPoint(x: bounds.maxX, y: bounds.minY),
            controlPoint2: CGPoint(x: bounds.maxX, y: bounds.minY)
        )
        path.line(to: CGPoint(x: bounds.maxX, y: bodyMaxY - radius))
        path.curve(
            to: CGPoint(x: bounds.maxX - radius, y: bodyMaxY),
            controlPoint1: CGPoint(x: bounds.maxX, y: bodyMaxY),
            controlPoint2: CGPoint(x: bounds.maxX, y: bodyMaxY)
        )
        path.line(to: CGPoint(x: arrowRight, y: bodyMaxY))
        path.line(to: CGPoint(x: centerX, y: bounds.maxY))
        path.line(to: CGPoint(x: arrowLeft, y: bodyMaxY))
        path.line(to: CGPoint(x: bounds.minX + radius, y: bodyMaxY))
        path.curve(
            to: CGPoint(x: bounds.minX, y: bodyMaxY - radius),
            controlPoint1: CGPoint(x: bounds.minX, y: bodyMaxY),
            controlPoint2: CGPoint(x: bounds.minX, y: bodyMaxY)
        )
        path.line(to: CGPoint(x: bounds.minX, y: bounds.minY + radius))
        path.curve(
            to: CGPoint(x: bounds.minX + radius, y: bounds.minY),
            controlPoint1: CGPoint(x: bounds.minX, y: bounds.minY),
            controlPoint2: CGPoint(x: bounds.minX, y: bounds.minY)
        )
        path.close()

        return path
    }
}
