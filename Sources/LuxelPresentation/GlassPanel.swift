import SwiftUI

public struct GlassPanel<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        if #available(macOS 26.0, *) {
            content
                .padding(16)
                .glassEffect(in: .rect(cornerRadius: 8))
        } else {
            content
                .padding(16)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
