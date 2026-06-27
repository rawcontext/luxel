import Foundation
import SwiftUI

extension URL {
    var isImageLikeMedia: Bool {
        switch pathExtension.lowercased() {
        case "gif", "heic", "jpeg", "jpg", "png", "tif", "tiff", "webp":
            true
        default:
            false
        }
    }
}

extension View {
    func luxelMenuSectionBackground(cornerRadius: CGFloat) -> some View {
        glassEffect(.clear, in: .rect(cornerRadius: cornerRadius))
    }

    func luxelMenuControlBackground(
        cornerRadius: CGFloat
    ) -> some View {
        modifier(
            LuxelMenuControlBackground(
                cornerRadius: cornerRadius
            )
        )
    }
}

struct LuxelMenuControlButtonStyle: ButtonStyle {
    let cornerRadius: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        LuxelMenuControlButtonBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            cornerRadius: cornerRadius
        )
    }
}

private struct LuxelMenuControlButtonBody<Label: View>: View {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    let label: Label
    let isPressed: Bool
    let cornerRadius: CGFloat

    var body: some View {
        label
            .glassEffect(
                .clear.interactive(isEnabled && (isHovered || isPressed)),
                in: .rect(cornerRadius: cornerRadius)
            )
            .scaleEffect(isPressed ? 0.97 : 1)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.08), value: isPressed)
    }
}

private struct LuxelMenuControlBackground: ViewModifier {
    @State private var isHovered = false

    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .glassEffect(.clear.interactive(isHovered), in: .rect(cornerRadius: cornerRadius))
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}
