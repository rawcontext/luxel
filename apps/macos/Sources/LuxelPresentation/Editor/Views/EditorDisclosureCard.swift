import SwiftUI

struct EditorDisclosureCard<Content: View>: View {
    @State private var isExpanded = false

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
        cardContainer
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var cardContainer: some View {
        if #available(macOS 26.0, *) {
            cardContent
                .glassEffect(in: .rect(cornerRadius: 8))
        } else {
            cardContent
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    SectionLabel(title)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.top, 16)
                .padding(.horizontal, 16)
                .padding(.bottom, isExpanded ? 12 : 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .padding(.horizontal, 16)

                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
