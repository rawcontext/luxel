import AppKit
import LuxelCore
import SwiftUI

extension NSEvent {
    var isMouseDown: Bool {
        switch type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            true
        default:
            false
        }
    }
}

final class NotchOverlayPanel: NSPanel {
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}

enum NotchRenderPhase: Equatable {
    case seed
    case settled
}

struct FlatTopIslandShape: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRoundedRect(
            in: rect,
            cornerRadii: RectangleCornerRadii(
                topLeading: 0,
                bottomLeading: cornerRadius,
                bottomTrailing: cornerRadius,
                topTrailing: 0
            ),
            style: .continuous
        )
        return path
    }
}

struct NotchSurfaceView: View {
    private static let appleNotchCornerRadius: CGFloat = 8
    private static let expandedActionTopInset: CGFloat = 8
    private static let pureBlack = Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1)
    private static let stopActionRed = Color(.sRGB, red: 0.72, green: 0.10, blue: 0.13, opacity: 1)

    @State private var hoveredActionID: NotchActivityActionID?

    let update: NotchPresentationUpdate
    let phase: NotchRenderPhase
    let onAction: @MainActor (NotchActivityActionID) -> Void
    let onDragArtifact: @MainActor (NotchArtifact) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            if update.activity != .dormant {
                islandSurface
                    .offset(y: -50)
                    .transition(.asymmetric(insertion: .identity, removal: .opacity))
            }
        }
        .frame(
            width: OverlayPanelNotchPresenter.panelSize.width,
            height: OverlayPanelNotchPresenter.panelSize.height
        )
        .ignoresSafeArea(.all)
        .animation(shellAnimation, value: phase)
        .animation(animation, value: update.presentationState)
        .animation(animation, value: update.activity)
        .accessibilityLabel(update.viewModel.accessibilityLabel)
    }

    var animation: Animation? {
        guard !update.motion.reducesMotion else {
            return .easeInOut(duration: update.motion.contentFadeDuration)
        }

        return .spring(
            response: update.motion.morphSpring.response,
            dampingFraction: update.motion.morphSpring.dampingRatio
        )
    }

    private var shellAnimation: Animation? {
        guard !update.motion.reducesMotion else {
            return .easeInOut(duration: update.motion.contentFadeDuration)
        }

        return .timingCurve(
            0.16, 0.92, 0.24, 1, duration: min(update.motion.geometryMorphDuration, 0.22))
    }

    private var contentAnimation: Animation? {
        guard !update.motion.reducesMotion else {
            return .easeInOut(duration: update.motion.contentFadeDuration)
        }

        return .easeOut(duration: update.motion.contentFadeDuration)
    }

    private var islandSurface: some View {
        expandedSurface
            .padding(.top, 2)
            .shadow(color: .black.opacity(0.5), radius: 22, y: 10)
    }

    private var expandedSurface: some View {
        ZStack(alignment: .topLeading) {
            FlatTopIslandShape(cornerRadius: expandedCornerRadius)
                .fill(Self.pureBlack)
                .overlay {
                    FlatTopIslandShape(cornerRadius: expandedCornerRadius)
                        .stroke(.white.opacity(phase == .seed ? 0 : 0.08), lineWidth: 0.8)
                }

            actionControls(buttonSize: 28, iconSize: 12, spacing: 5)
                .frame(width: expandedWidth, height: expandedHeight, alignment: .center)
                .padding(.top, Self.expandedActionTopInset)
                .opacity(update.viewModel.actions.isEmpty ? 0 : 1)
                .opacity(phase == .settled ? 1 : 0)
                .scaleEffect(phase == .seed ? 0.92 : 1, anchor: .top)
                .animation(contentAnimation, value: phase)
        }
        .frame(width: expandedWidth, height: expandedHeight, alignment: .topLeading)
        .scaleEffect(
            x: phase == .seed ? seedWidth / expandedWidth : 1,
            y: phase == .seed ? seedHeight / expandedHeight : 1,
            anchor: .top
        )
    }

    private func actionControls(
        buttonSize: CGFloat,
        iconSize: CGFloat,
        spacing: CGFloat
    ) -> some View {
        ZStack(alignment: .top) {
            actionRow(buttonSize: buttonSize, iconSize: iconSize, spacing: spacing)

            if let hoveredAction {
                notchActionTooltip(for: hoveredAction)
                    .offset(y: buttonSize + 5)
                    .transition(.opacity)
            }
        }
    }

    private func actionRow(
        buttonSize: CGFloat = 34,
        iconSize: CGFloat = 14,
        spacing: CGFloat = 9
    ) -> some View {
        return HStack(spacing: 0) {
            Spacer(minLength: spacing)

            ForEach(update.viewModel.actions.indices, id: \.self) { index in
                let action = update.viewModel.actions[index]

                Button {
                    onAction(action.id)
                } label: {
                    Image(systemName: action.systemImage)
                        .font(.system(size: iconSize, weight: .semibold))
                        .frame(width: iconSize, height: iconSize, alignment: .center)
                        .frame(width: buttonSize, height: buttonSize)
                        .foregroundStyle(actionForeground(action))
                        .background(actionBackground(action), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(action.title))
                .help(Text(action.title))
                .onHover { isHovered in
                    if isHovered {
                        hoveredActionID = action.id
                    } else if hoveredActionID == action.id {
                        hoveredActionID = nil
                    }
                }

                if index < update.viewModel.actions.count - 1 {
                    Spacer(minLength: spacing)
                    Spacer(minLength: spacing)
                }
            }

            Spacer(minLength: spacing)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func notchActionTooltip(for action: NotchActivityActionDescriptor) -> some View {
        Text(action.title)
            .font(.system(size: 11, weight: .semibold))
            .lineLimit(1)
            .foregroundStyle(.white.opacity(0.92))
            .padding(.horizontal, 8)
            .frame(height: 18)
            .background(.white.opacity(0.13), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(.white.opacity(0.12), lineWidth: 0.7)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var hoveredAction: NotchActivityActionDescriptor? {
        guard let hoveredActionID else {
            return nil
        }

        return update.viewModel.actions.first { $0.id == hoveredActionID }
    }

    private func actionForeground(_ action: NotchActivityActionDescriptor) -> Color {
        if action.id == .stopRecording {
            return .white
        }

        switch action.role {
        case .destructive:
            return .red
        case .primary:
            return .black
        case .standard:
            return .white
        }
    }

    private func actionBackground(_ action: NotchActivityActionDescriptor) -> Color {
        if action.id == .stopRecording {
            return Self.stopActionRed
        }

        switch action.role {
        case .destructive:
            return .red.opacity(0.16)
        case .primary:
            return .white
        case .standard:
            return .white.opacity(0.12)
        }
    }

    private var expandedWidth: CGFloat {
        notchWidth
    }

    private var expandedHeight: CGFloat {
        OverlayPanelNotchPresenter.expandedHeight
    }

    private var seedWidth: CGFloat {
        notchWidth
    }

    private var seedHeight: CGFloat {
        34
    }

    private var expandedCornerRadius: CGFloat {
        Self.appleNotchCornerRadius
    }

    private var notchWidth: CGFloat {
        OverlayPanelNotchPresenter.notchWidth(for: update.geometry)
    }
}

extension NotchScreenRect {
    var nsRect: NSRect {
        NSRect(
            x: originX,
            y: originY,
            width: width,
            height: height
        )
    }
}
