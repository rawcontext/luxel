import SwiftUI

struct LuxelGlassCircleButtonBody<Label: View>: View {
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
