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
            .opacity(isEnabled ? 1 : 0.45)
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
        guard isEnabled else {
            return 0.18
        }

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

enum LuxelMenuIslandStyle {
    static let fillTop = Color(red: 74 / 255, green: 74 / 255, blue: 92 / 255).opacity(0.52)
    static let fillBottom = Color(red: 30 / 255, green: 30 / 255, blue: 40 / 255).opacity(0.62)
    static let recordRedTop = Color(red: 1.0, green: 0.43, blue: 0.39)
    static let recordRedBottom = Color(red: 0.86, green: 0.2, blue: 0.16)
    static let recordGlow = Color(red: 1.0, green: 0.27, blue: 0.23)
}

struct LuxelIslandButtonStyle: ButtonStyle {
    let cornerRadius: CGFloat
    var fillOpacity: Double = 0.09
    var dimsWhenDisabled = true

    func makeBody(configuration: Configuration) -> some View {
        LuxelIslandButtonBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            cornerRadius: cornerRadius,
            fillOpacity: fillOpacity,
            dimsWhenDisabled: dimsWhenDisabled
        )
    }
}

private struct LuxelIslandButtonBody<Label: View>: View {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    let label: Label
    let isPressed: Bool
    let cornerRadius: CGFloat
    let fillOpacity: Double
    let dimsWhenDisabled: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        label
            .opacity(dimsWhenDisabled && !isEnabled ? 0.45 : 1)
            .background {
                shape
                    .fill(.white.opacity(currentFillOpacity))
                    .overlay {
                        shape
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(0.1), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    }
            }
            .scaleEffect(isPressed ? 0.95 : 1)
            .contentShape(shape)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.08), value: isPressed)
    }

    private var currentFillOpacity: Double {
        guard isEnabled else {
            return fillOpacity
        }

        if isPressed {
            return fillOpacity + 0.1
        }

        if isHovered {
            return fillOpacity + 0.07
        }

        return fillOpacity
    }
}

struct LuxelIslandCellButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .luxelIslandCellHighlight(isPressed: configuration.isPressed)
    }
}

private struct LuxelIslandCellHighlight: ViewModifier {
    @State private var isHovered = false

    let isPressed: Bool

    func body(content: Content) -> some View {
        content
            .background(.white.opacity(isPressed ? 0.12 : isHovered ? 0.09 : 0))
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

private struct LuxelIslandControlGroupBackground: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .clipShape(shape)
            .background {
                shape.fill(.white.opacity(0.07))
            }
            .overlay {
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.08), .clear],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func luxelIslandCellHighlight(isPressed: Bool = false) -> some View {
        modifier(LuxelIslandCellHighlight(isPressed: isPressed))
    }

    func luxelIslandControlGroupBackground(cornerRadius: CGFloat) -> some View {
        modifier(LuxelIslandControlGroupBackground(cornerRadius: cornerRadius))
    }
}

extension View {
    func luxelMenuIslandBackground(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return glassEffect(.clear, in: .rect(cornerRadius: cornerRadius))
            .background(
                LinearGradient(
                    colors: [LuxelMenuIslandStyle.fillTop, LuxelMenuIslandStyle.fillBottom],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                in: shape
            )
            .overlay {
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.18), .white.opacity(0.06)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.4), radius: 18, y: 10)
    }
}
