import SwiftUI

struct ResizeHandleDot: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            Circle()
                .fill(.white.opacity(0.74))
                .frame(width: 12, height: 12)
                .glassEffect(in: .circle)
        } else {
            Circle()
                .fill(.regularMaterial)
                .frame(width: 12, height: 12)
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.72), lineWidth: 1)
                }
        }
    }
}
