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
        background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    func luxelMenuControlBackground(cornerRadius: CGFloat, isActive: Bool = false) -> some View {
        background(
            .white.opacity(isActive ? 0.14 : 0.09),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }
}
