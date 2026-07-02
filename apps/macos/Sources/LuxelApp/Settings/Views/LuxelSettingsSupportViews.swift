import SwiftUI

enum LuxelSettingsPane: CaseIterable, Identifiable {
    case recording
    case output
    case presets
    case shortcuts
    case notch
    case experimental
    case commandLine
    case system

    var id: Self {
        self
    }

    var title: String {
        switch self {
        case .recording:
            "Recording"
        case .output:
            "Output"
        case .presets:
            "Presets"
        case .shortcuts:
            "Shortcuts"
        case .notch:
            "Notch"
        case .experimental:
            "Experimental"
        case .commandLine:
            "Command Line"
        case .system:
            "System"
        }
    }

    var subtitle: String {
        switch self {
        case .recording:
            "Capture, audio, and camera controls for new recordings."
        case .output:
            "Where recordings go and how exports behave."
        case .presets:
            "Reusable export presets and cropper size presets."
        case .shortcuts:
            "Keyboard shortcuts and URL automation."
        case .notch:
            "Built-in notch display controls and fallback behavior."
        case .experimental:
            "Preview features that are still being built out."
        case .commandLine:
            "Install and configure the luxel command-line tool."
        case .system:
            "App startup, updates, menu bar behavior, and acknowledgements."
        }
    }

    var systemImage: String {
        switch self {
        case .recording:
            "record.circle"
        case .output:
            "tray.and.arrow.down"
        case .presets:
            "slider.horizontal.3"
        case .shortcuts:
            "keyboard"
        case .notch:
            "laptopcomputer"
        case .experimental:
            "sparkles"
        case .commandLine:
            "terminal"
        case .system:
            "gearshape"
        }
    }

}

struct ExperimentalBadge: View {
    var body: some View {
        Text("Experimental")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.orange)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.orange.opacity(0.14), in: Capsule())
    }
}

struct SettingsSidebarSelectionBackground: View {
    let isSelected: Bool

    var body: some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.primary.opacity(0.08))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                }
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.clear)
        }
    }
}

struct SettingsGlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let padding: CGFloat
    let tint: Color
    let content: Content

    init(
        cornerRadius: CGFloat,
        padding: CGFloat,
        tint: Color = .clear,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            content
                .padding(padding)
                .glassEffect(.regular.tint(tint), in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .padding(padding)
                .background(
                    .regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(0.12), lineWidth: 1)
                }
        }
    }
}
