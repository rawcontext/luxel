import SwiftUI

public extension View {
    func luxelGlassCapsuleBackground() -> some View {
        background {
            Capsule(style: .continuous)
                .fill(LuxelGlassTheme.controlFill)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [LuxelGlassTheme.controlHighlight, .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
        }
        .contentShape(Capsule(style: .continuous))
    }
}

public struct LuxelGlassSwitchToggleStyle: ToggleStyle {
    private let showsLabel: Bool

    public init(showsLabel: Bool = true) {
        self.showsLabel = showsLabel
    }

    public func makeBody(configuration: Configuration) -> some View {
        LuxelGlassSwitchBody(configuration: configuration, showsLabel: showsLabel)
    }
}

private struct LuxelGlassSwitchBody: View {
    @Environment(\.isEnabled) private var isEnabled

    let configuration: ToggleStyleConfiguration
    let showsLabel: Bool

    @ViewBuilder
    var body: some View {
        if showsLabel {
            HStack(spacing: 12) {
                configuration.label
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.white.opacity(isEnabled ? 0.95 : 0.45))

                Spacer(minLength: 12)

                switchCapsule
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: toggle)
        } else {
            switchCapsule
                .contentShape(Rectangle())
                .onTapGesture(perform: toggle)
        }
    }

    private func toggle() {
        guard isEnabled else {
            return
        }

        configuration.isOn.toggle()
    }

    private var switchCapsule: some View {
        ZStack(alignment: configuration.isOn ? .trailing : .leading) {
            Capsule(style: .continuous)
                .fill(.white.opacity(trackOpacity))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(.black.opacity(0.12), lineWidth: 0.5)
                }

            Circle()
                .fill(knobColor)
                .frame(width: 20, height: 20)
                .shadow(color: .black.opacity(0.4), radius: 1.5, y: 1)
                .padding(2)
        }
        .frame(width: 40, height: 24)
        .animation(.easeOut(duration: 0.15), value: configuration.isOn)
        .opacity(isEnabled ? 1 : 0.5)
    }

    private var trackOpacity: Double {
        configuration.isOn ? 0.9 : 0.14
    }

    private var knobColor: Color {
        configuration.isOn
            ? Color(red: 35 / 255, green: 35 / 255, blue: 46 / 255)
            : .white.opacity(0.85)
    }
}

public struct LuxelGlassCheckboxToggleStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        LuxelGlassCheckboxBody(configuration: configuration)
    }
}

private struct LuxelGlassCheckboxBody: View {
    @Environment(\.isEnabled) private var isEnabled

    let configuration: ToggleStyleConfiguration

    var body: some View {
        HStack(spacing: 9) {
            checkbox

            configuration.label
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(labelOpacity))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard isEnabled else {
                return
            }

            configuration.isOn.toggle()
        }
    }

    private var checkbox: some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(.white.opacity(boxOpacity))
            .overlay {
                if configuration.isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(LuxelGlassTheme.prominentText)
                } else {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                }
            }
            .frame(width: 17, height: 17)
            .animation(.easeOut(duration: 0.12), value: configuration.isOn)
    }

    private var boxOpacity: Double {
        guard isEnabled else {
            return configuration.isOn ? 0.35 : 0.08
        }

        return configuration.isOn ? 0.9 : 0.12
    }

    private var labelOpacity: Double {
        isEnabled ? 0.9 : 0.45
    }
}

public struct LuxelGlassTitleLabel: View {
    private let title: String
    private let systemImage: String?
    private let fontSize: CGFloat

    public init(_ title: String, systemImage: String? = nil, fontSize: CGFloat = 12.5) {
        self.title = title
        self.systemImage = systemImage
        self.fontSize = fontSize
    }

    public var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
            }
            Text(title)
                .font(.system(size: fontSize, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

public struct LuxelGlassMenuLabel: View {
    private let title: String
    private let systemImage: String?
    private let fillsAvailableWidth: Bool

    public init(_ title: String, systemImage: String? = nil, fillsAvailableWidth: Bool = false) {
        self.title = title
        self.systemImage = systemImage
        self.fillsAvailableWidth = fillsAvailableWidth
    }
    public var body: some View {
        HStack(spacing: 6) {
            LuxelGlassTitleLabel(title, systemImage: systemImage)

            if fillsAvailableWidth {
                Spacer(minLength: 6)
            }
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8.5, weight: .bold))
                .opacity(0.6)
        }
        .frame(maxWidth: fillsAvailableWidth ? .infinity : nil)
        .foregroundStyle(.white.opacity(0.92))
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.vertical, 7)
        .luxelGlassCapsuleBackground()
    }
}

public struct LuxelGlassSegmentedPicker<Option: Hashable>: View {
    @Binding private var selection: Option
    private let options: [Option]
    private let label: (Option) -> String

    public init(
        selection: Binding<Option>,
        options: [Option],
        label: @escaping (Option) -> String
    ) {
        _selection = selection
        self.options = options
        self.label = label
    }

    public var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.self) { option in
                segment(option)
            }
        }
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.black.opacity(0.2))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.black.opacity(0.2), lineWidth: 0.5)
                }
        }
    }

    private func segment(_ option: Option) -> some View {
        let isSelected = option == selection

        return Button {
            selection = option
        } label: {
            Text(label(option))
                .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(.white.opacity(isSelected ? 0.95 : 0.5))
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(.white.opacity(0.16))
                            .overlay {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [.white.opacity(0.2), .clear],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ),
                                        lineWidth: 1
                                    )
                            }
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: selection)
    }
}

public struct LuxelGlassPillButtonStyle: ButtonStyle {
    private let isProminent: Bool

    public init(isProminent: Bool = false) {
        self.isProminent = isProminent
    }

    public func makeBody(configuration: Configuration) -> some View {
        LuxelGlassPillButtonBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            isProminent: isProminent
        )
    }
}

private struct LuxelGlassPillButtonBody<Label: View>: View {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    let label: Label
    let isPressed: Bool
    let isProminent: Bool

    var body: some View {
        label
            .font(.system(size: 12.5, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .frame(minHeight: 38)
            .frame(maxWidth: .infinity)
            .background {
                Capsule(style: .continuous)
                    .fill(fill)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [.white.opacity(isProminent ? 0 : 0.12), .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    }
                    .shadow(
                        color: .black.opacity(isProminent && isEnabled ? 0.3 : 0),
                        radius: 9,
                        y: 3
                    )
            }
            .contentShape(Capsule(style: .continuous))
            .scaleEffect(isPressed ? 0.96 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.08), value: isPressed)
    }

    private var foreground: Color {
        isProminent ? LuxelGlassTheme.prominentText : .white.opacity(0.85)
    }

    private var fill: Color {
        if isProminent {
            return .white.opacity(isHovered && isEnabled ? 1 : 0.92)
        }

        return .white.opacity(isHovered && isEnabled ? 0.15 : 0.08)
    }
}

public struct LuxelGlassCircleButtonStyle: ButtonStyle {
    private let side: CGFloat

    public init(side: CGFloat = 30) {
        self.side = side
    }

    public func makeBody(configuration: Configuration) -> some View {
        LuxelGlassCircleButtonBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            side: side
        )
    }
}

private struct LuxelGlassCircleButtonBody<Label: View>: View {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    let label: Label
    let isPressed: Bool
    let side: CGFloat

    var body: some View {
        label
            .labelStyle(.iconOnly)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white.opacity(isEnabled ? 0.8 : 0.35))
            .frame(width: side, height: side)
            .background {
                Circle()
                    .fill(.white.opacity(isHovered && isEnabled ? 0.15 : 0.08))
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(0.1), lineWidth: 1)
                    }
            }
            .contentShape(Circle())
            .scaleEffect(isPressed ? 0.92 : 1)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
            .animation(.easeOut(duration: 0.08), value: isPressed)
    }
}

extension View {
    public func luxelGlassFieldBackground(cornerRadius: CGFloat = 12) -> some View {
        padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(LuxelGlassTheme.controlFill)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                LinearGradient(
                                    colors: [LuxelGlassTheme.controlHighlight, .clear],
                                    startPoint: .top,
                                    endPoint: .bottom
                                ),
                                lineWidth: 1
                            )
                    }
            }
    }
}
