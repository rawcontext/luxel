import SwiftUI

struct EditorDisclosureCard<Content: View>: View {
    @State private var isExpanded = true

    private let title: String
    private let content: Content

    init(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        LuxelGlassIsland(cornerRadius: 18) {
            cardContent
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .kerning(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.45))

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .padding(.top, 12)
                .padding(.horizontal, 14)
                .padding(.bottom, isExpanded ? 10 : 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
