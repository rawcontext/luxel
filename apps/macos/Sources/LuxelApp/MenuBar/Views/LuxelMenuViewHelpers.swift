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
    static let fillTop = Color(red: 74 / 255, green: 74 / 255, blue: 92 / 255).opacity(0.22)
    static let fillBottom = Color(red: 30 / 255, green: 30 / 255, blue: 40 / 255).opacity(0.34)
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

enum LuxelIslandCellCorners {
    case leading
    case trailing
    case all

    func shape(cornerRadius: CGFloat) -> UnevenRoundedRectangle {
        switch self {
        case .leading:
            UnevenRoundedRectangle(
                topLeadingRadius: cornerRadius,
                bottomLeadingRadius: cornerRadius,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0,
                style: .continuous
            )
        case .trailing:
            UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: cornerRadius,
                topTrailingRadius: cornerRadius,
                style: .continuous
            )
        case .all:
            UnevenRoundedRectangle(
                cornerRadii: .init(
                    topLeading: cornerRadius,
                    bottomLeading: cornerRadius,
                    bottomTrailing: cornerRadius,
                    topTrailing: cornerRadius
                ), style: .continuous)
        }
    }
}

struct LuxelIslandCellButtonStyle: ButtonStyle {
    let corners: LuxelIslandCellCorners
    let cornerRadius: CGFloat

    init(corners: LuxelIslandCellCorners = .all, cornerRadius: CGFloat = 0) {
        self.corners = corners
        self.cornerRadius = cornerRadius
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .luxelIslandCellHighlight(
                isPressed: configuration.isPressed,
                corners: corners,
                cornerRadius: cornerRadius
            )
    }
}

private struct LuxelIslandCellHighlight: ViewModifier {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    let isPressed: Bool
    let corners: LuxelIslandCellCorners
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = corners.shape(cornerRadius: cornerRadius)

        content
            .background {
                shape.fill(.white.opacity(fillOpacity))
            }
            .contentShape(shape)
            .onHover { isHovered = isEnabled && $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.08), value: isPressed)
    }

    private var fillOpacity: Double {
        guard isEnabled else {
            return 0
        }

        if isPressed {
            return 0.1
        }

        return isHovered ? 0.07 : 0
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
    func luxelIslandCellHighlight(
        isPressed: Bool = false,
        corners: LuxelIslandCellCorners = .all,
        cornerRadius: CGFloat = 0
    ) -> some View {
        modifier(
            LuxelIslandCellHighlight(
                isPressed: isPressed,
                corners: corners,
                cornerRadius: cornerRadius
            ))
    }

    func luxelIslandControlGroupBackground(cornerRadius: CGFloat) -> some View {
        modifier(LuxelIslandControlGroupBackground(cornerRadius: cornerRadius))
    }
}

extension View {
    func luxelMenuIslandBackground(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        return
            self
            .glassEffect(.clear, in: .rect(cornerRadius: cornerRadius))
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
            .clipShape(shape)
    }
}
