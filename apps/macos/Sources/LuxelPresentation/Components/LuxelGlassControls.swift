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
            .background(LuxelGlassTheme.islandFill, in: shape)
            .overlay {
                shape
                    .strokeBorder(
                        LinearGradient(
                            colors: [LuxelGlassTheme.islandHighlight, .clear],
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
