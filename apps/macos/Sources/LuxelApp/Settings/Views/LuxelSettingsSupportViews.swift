import LuxelCore
import LuxelPresentation
import SwiftUI

enum LuxelSettingsPane: CaseIterable, Identifiable {
    case recording
    case output
    case presets
    case shortcuts
    case notch
    case replayBuffer
    case notifications
    case transcripts
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
        case .replayBuffer:
            "Replay Buffer"
        case .notifications:
            LuxelLocalization.string(
                "settings.notifications.sidebar.title",
                defaultValue: "Notifications"
            )
        case .transcripts:
            "Transcripts"
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
        case .replayBuffer:
            "Always-on recent capture and clip behavior."
        case .notifications:
            LuxelLocalization.string(
                "settings.notifications.sidebar.subtitle",
                defaultValue: "System delivery and notification types."
            )
        case .transcripts:
            "Transcription language, turn segmentation, and speaker identification."
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
        case .replayBuffer:
            "gobackward"
        case .notifications:
            "bell.badge"
        case .transcripts:
            "text.alignleft"
        case .commandLine:
            "terminal"
        case .system:
            "gearshape"
        }
    }

}

struct SettingsSidebarSelectionBackground: View {
    @State private var isHovered = false

    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 15, style: .continuous)
            .fill(.white.opacity(isSelected ? 0.14 : isHovered ? 0.07 : 0))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.18), .clear],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                }
            }
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

struct SettingsIslandGroup<Content: View>: View {
    private let header: String?
    private let footer: String?
    private let content: Content

    init(
        _ header: String? = nil,
        footer: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.header = header
        self.footer = footer
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let header {
                LuxelGlassSectionHeader(header)
                    .padding(.leading, 6)
                    .padding(.bottom, 10)
            }

            LuxelGlassIsland(cornerRadius: 20) {
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }

            if let footer {
                LuxelGlassSectionFooter(footer)
                    .padding(.leading, 6)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsRow<Content: View>: View {
    private let title: String?
    private let content: Content

    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            if let title {
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.95))

                Spacer(minLength: 12)
            }

            content
        }
        .frame(minHeight: LuxelGlassTheme.settingsRowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SettingsMenuPicker<Option: Hashable>: View {
    @Binding var selection: Option
    let options: [Option]
    let optionLabel: (Option) -> String

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    if option == selection {
                        Label(optionLabel(option), systemImage: "checkmark")
                    } else {
                        Text(optionLabel(option))
                    }
                }
            }
        } label: {
            LuxelGlassMenuLabel(optionLabel(selection))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
    }
}

struct SettingsCapsuleButtonLabel: View {
    private let title: String
    private let systemImage: String?

    init(_ title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        LuxelGlassTitleLabel(title, systemImage: systemImage)
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .luxelGlassCapsuleBackground()
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
