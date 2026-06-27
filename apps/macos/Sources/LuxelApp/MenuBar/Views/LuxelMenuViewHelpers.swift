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
            .background(
                Color.black.opacity(LuxelMenuGlassContrast.sectionOpacity),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
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
    let addsContrastBackground: Bool

    init(cornerRadius: CGFloat, addsContrastBackground: Bool = true) {
        self.cornerRadius = cornerRadius
        self.addsContrastBackground = addsContrastBackground
    }

    func makeBody(configuration: Configuration) -> some View {
        LuxelMenuControlButtonBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            cornerRadius: cornerRadius,
            addsContrastBackground: addsContrastBackground
        )
    }
}

private struct LuxelMenuControlButtonBody<Label: View>: View {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    let label: Label
    let isPressed: Bool
    let cornerRadius: CGFloat
    let addsContrastBackground: Bool

    var body: some View {
        label
            .glassEffect(
                .clear.interactive(isEnabled && (isHovered || isPressed)),
                in: .rect(cornerRadius: cornerRadius)
            )
            .background {
                if addsContrastBackground {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.black.opacity(buttonContrastOpacity))
                }
            }
            .scaleEffect(isPressed ? 0.97 : 1)
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.08), value: isPressed)
    }

    private var buttonContrastOpacity: Double {
        if isPressed {
            return LuxelMenuGlassContrast.pressedOpacity
        }

        if isHovered {
            return LuxelMenuGlassContrast.hoverOpacity
        }

        return LuxelMenuGlassContrast.controlOpacity
    }
}

private struct LuxelMenuControlBackground: ViewModifier {
    @State private var isHovered = false

    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .glassEffect(.clear.interactive(isHovered), in: .rect(cornerRadius: cornerRadius))
            .background(
                Color.black.opacity(
                    isHovered ? LuxelMenuGlassContrast.hoverOpacity : LuxelMenuGlassContrast.controlOpacity
                ),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

private enum LuxelMenuGlassContrast {
    static let sectionOpacity = 0.42
    static let controlOpacity = 0.46
    static let hoverOpacity = 0.52
    static let pressedOpacity = 0.58
}
