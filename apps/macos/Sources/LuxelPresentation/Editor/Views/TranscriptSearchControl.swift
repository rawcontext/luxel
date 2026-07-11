import SwiftUI

struct TranscriptSearchControl: View {
    @Binding var query: String

    let selectedMatchIndex: Int?
    let matchCount: Int
    let selectPrevious: () -> Void
    let selectNext: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))

                TextField("Search", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .onSubmit { selectNext() }
                    .help("Search the transcript.")

                Text(counterText)
                    .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(counterForegroundStyle)
                    .layoutPriority(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(width: 170)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.black.opacity(0.22))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                    }
            }

            if matchCount > 0 {
                Button(action: selectPrevious) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(LuxelGlassCircleButtonStyle(side: 24))
                .help("Previous match")
                .accessibilityLabel("Previous transcript search match")

                Button(action: selectNext) {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(LuxelGlassCircleButtonStyle(side: 24))
                .help("Next match")
                .accessibilityLabel("Next transcript search match")
            }
        }
        .animation(.easeOut(duration: 0.15), value: matchCount > 0)
    }

    private var counterText: String {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "0/0"
        }
        return "\(selectedMatchIndex.map { $0 + 1 } ?? 0)/\(matchCount)"
    }

    private var counterForegroundStyle: Color {
        if matchCount == 0, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .red
        }
        return .white.opacity(0.4)
    }
}
