import AppKit
import SwiftUI

public enum LuxelGlassTheme {
    public static let windowFillTop = Color(red: 74 / 255, green: 74 / 255, blue: 92 / 255)
        .opacity(0.22)
    public static let windowFillBottom = Color(red: 30 / 255, green: 30 / 255, blue: 40 / 255)
        .opacity(0.34)
    public static let islandFill = Color.white.opacity(0.05)
    public static let islandHighlight = Color.white.opacity(0.07)
    public static let rowDivider = Color.white.opacity(0.07)
    public static let controlFill = Color.white.opacity(0.09)
    public static let controlHighlight = Color.white.opacity(0.12)
    public static let settingsRowHeight: CGFloat = 48
    public static let prominentText = Color(red: 22 / 255, green: 22 / 255, blue: 29 / 255)
}

public struct LuxelGlassWindowBackground: View {
    public init() {}

    public var body: some View {
        ZStack {
            BehindWindowBlurView()

            LinearGradient(
                colors: [LuxelGlassTheme.windowFillTop, LuxelGlassTheme.windowFillBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }
}

private struct BehindWindowBlurView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .hudWindow
        view.state = .active
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

public struct LuxelGlassWindowChromeConfigurator: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> LuxelGlassWindowEnforcerView {
        LuxelGlassWindowEnforcerView(configuration: .chrome)
    }

    public func updateNSView(
        _ nsView: LuxelGlassWindowEnforcerView,
        context: Context
    ) {
        nsView.enforceWindowConfiguration()
    }
}

public struct LuxelGlassWindowTransparencyConfigurator: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> LuxelGlassWindowEnforcerView {
        LuxelGlassWindowEnforcerView(configuration: .transparency)
    }

    public func updateNSView(
        _ nsView: LuxelGlassWindowEnforcerView,
        context: Context
    ) {
        nsView.enforceWindowConfiguration()
    }
}

public extension View {
    func luxelGlassSceneWindowChrome() -> some View {
        containerBackground(.clear, for: .window)
            .toolbar(removing: .title)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
            .windowMinimizeBehavior(.enabled)
            .windowResizeBehavior(.enabled)
            .windowFullScreenBehavior(.enabled)
    }
}

@MainActor
public enum LuxelGlassWindowChrome {
    public static func configure(_ window: NSWindow) {
        let requiredStyleMask: NSWindow.StyleMask = [
            .titled,
            .closable,
            .miniaturizable,
            .resizable,
            .fullSizeContentView
        ]
        if !window.styleMask.isSuperset(of: requiredStyleMask) {
            window.styleMask.formUnion(requiredStyleMask)
        }

        if !window.titlebarAppearsTransparent {
            window.titlebarAppearsTransparent = true
        }

        if window.titleVisibility != .visible {
            window.titleVisibility = .visible
        }

        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for button in buttons {
            if let windowButton = window.standardWindowButton(button), windowButton.isHidden {
                windowButton.isHidden = false
            }
        }

        LuxelGlassWindowTransparency.configure(window)
    }
}

@MainActor
public enum LuxelGlassWindowTransparency {
    public static func configure(_ window: NSWindow) {
        if window.isOpaque {
            window.isOpaque = false
        }

        if window.backgroundColor != .clear {
            window.backgroundColor = .clear
        }
    }
}

// SwiftUI re-asserts `isOpaque = true` on scene windows when they become key,
// which silently disables behind-window blur sampling. Re-enforce transparency
// on every window activation/occlusion change so the glass chrome survives focus.
public final class LuxelGlassWindowEnforcerView: NSView {
    enum Configuration {
        case chrome
        case transparency
    }

    private let configuration: Configuration
    private var observers: [NSObjectProtocol] = []

    init(configuration: Configuration) {
        self.configuration = configuration
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        removeObservers()

        guard let window else {
            return
        }

        enforceWindowConfiguration()

        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didResignMainNotification,
            NSWindow.didChangeOcclusionStateNotification
        ]
        observers = names.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.enforceWindowConfiguration()
                }
            }
        }
    }

    func enforceWindowConfiguration() {
        guard let window else {
            return
        }

        switch configuration {
        case .chrome:
            LuxelGlassWindowChrome.configure(window)
        case .transparency:
            LuxelGlassWindowTransparency.configure(window)
        }
    }

    private func removeObservers() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
    }
}

public struct LuxelGlassIsland<Content: View>: View {
    private let cornerRadius: CGFloat
    private let content: Content

    public init(cornerRadius: CGFloat = 20, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        content
            .glassEffect(.clear, in: .rect(cornerRadius: cornerRadius))
            .background(
                LinearGradient(
                    colors: [LuxelGlassTheme.windowFillTop, LuxelGlassTheme.windowFillBottom],
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

public struct LuxelGlassSectionHeader: View {
    private let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .kerning(1)
            .textCase(.uppercase)
            .foregroundStyle(.white.opacity(0.45))
    }
}

public struct LuxelGlassSectionFooter: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(.white.opacity(0.4))
            .fixedSize(horizontal: false, vertical: true)
    }
}

public struct LuxelGlassRowDivider: View {
    public init() {}

    public var body: some View {
        Rectangle()
            .fill(LuxelGlassTheme.rowDivider)
            .frame(height: 1)
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

public struct LuxelGlassMenuLabel: View {
    private let title: String
    private let systemImage: String?

    public init(_ title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    public var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
            }

            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8.5, weight: .bold))
                .opacity(0.6)
        }
        .foregroundStyle(.white.opacity(0.92))
        .padding(.leading, 12)
        .padding(.trailing, 10)
        .padding(.vertical, 7)
        .background {
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
