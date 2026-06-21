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
        background(
            .white.opacity(0.09), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func luxelMenuControlBackground(
        cornerRadius: CGFloat,
        isActive: Bool = false,
        idleOpacity: Double? = nil,
        hoverOpacity: Double? = nil
    ) -> some View {
        modifier(
            LuxelMenuControlBackground(
                cornerRadius: cornerRadius,
                isActive: isActive,
                idleOpacity: idleOpacity,
                hoverOpacity: hoverOpacity
            )
        )
    }
}

private struct LuxelMenuControlBackground: ViewModifier {
    @State private var isHovered = false

    let cornerRadius: CGFloat
    let isActive: Bool
    let idleOpacity: Double?
    let hoverOpacity: Double?

    func body(content: Content) -> some View {
        content
            .background(
                .white.opacity(backgroundOpacity),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .glassEffect(.regular.interactive(isHovered), in: .rect(cornerRadius: cornerRadius))
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private var backgroundOpacity: Double {
        if isHovered, let hoverOpacity {
            return hoverOpacity
        }

        if !isHovered, let idleOpacity {
            return idleOpacity
        }

        return switch (isActive, isHovered) {
        case (true, true):
            0.18
        case (true, false):
            0.14
        case (false, true):
            0.13
        case (false, false):
            0.09
        }
    }
}
